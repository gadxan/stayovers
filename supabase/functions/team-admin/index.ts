// Stayover Mikocheni — team management (Supabase Edge Function "team-admin").
//
// Lets an OWNER list the team, add people, change roles, reset passwords,
// disable or remove access. Changing logins needs Supabase's secret key, which must
// never reach the browser, so it lives here on the server.
//
// Security:
//  - Deployed with verify_jwt = false (required for the new sb_ keys); the caller's
//    session is verified below with auth.getUser, and only owners get past that.
//  - Owners can't demote, disable or remove themselves, and the last owner can't be
//    demoted, disabled or removed, so the business can't be locked out.

import { createClient } from "npm:@supabase/supabase-js@2.118.0";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const fail = (message: string, status = 400) => json({ error: message }, status);

function secretKey(): string {
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (raw) {
    try {
      const k = JSON.parse(raw)["default"];
      if (k) return k;
    } catch { /* fall back to the legacy key */ }
  }
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!legacy) throw new Error("No server key available");
  return legacy;
}

const ROLES = ["owner", "staff"];
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const FOREVER = "876000h"; // ~100 years: how Supabase expresses "disabled"

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return fail("Use POST", 405);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, secretKey(), {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ---- who is calling? ----
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token || token.startsWith("sb_")) return fail("Sign in first.", 401);
  const { data: who, error: whoErr } = await admin.auth.getUser(token);
  if (whoErr || !who?.user) return fail("Your session has expired. Sign in again.", 401);
  const me = who.user;
  const { data: myProfile } = await admin.from("profiles").select("role").eq("id", me.id).maybeSingle();
  if (myProfile?.role !== "owner") return fail("Only owners can manage the team.", 403);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return fail("Bad request."); }
  const action = String(body.action || "");
  const userId = typeof body.userId === "string" ? body.userId : "";
  const redirectTo = typeof body.redirectTo === "string" && /^https?:\/\//.test(body.redirectTo) ? body.redirectTo : undefined;

  const ownerCount = async () => {
    const { count } = await admin.from("profiles").select("id", { count: "exact", head: true }).eq("role", "owner").is("removed_at", null);
    return count ?? 0;
  };
  const roleOf = async (id: string) =>
    (await admin.from("profiles").select("role").eq("id", id).maybeSingle()).data?.role as string | undefined;
  const guardTarget = async (what: string) => {
    if (!userId) return "Choose a person.";
    if (userId === me.id) return `You can’t ${what} yourself.`;
    if ((await roleOf(userId)) === "owner" && (await ownerCount()) <= 1) return `You can’t ${what} the only owner.`;
    return null;
  };
  // Every team action is written to the change log (History tab), never with passwords.
  const log = async (action: string, targetId: string, detail: Record<string, unknown>) => {
    await admin.from("audit_log").insert({
      actor: me.id, actor_email: me.email, table_name: "team", row_id: targetId,
      action: `team.${action}`, new_data: detail,
    });
  };
  const emailOf = async (id: string) => (await admin.auth.admin.getUserById(id)).data?.user?.email || "";
  const setProfile = async (id: string, patch: Record<string, unknown>) => {
    // the sign-up trigger normally creates the profile; make sure it exists either way
    const { error } = await admin.from("profiles").upsert({ id, ...patch }, { onConflict: "id" });
    if (error) throw error;
  };

  try {
    switch (action) {
      case "list": {
        const users = [];
        for (let page = 1; page < 50; page++) {
          const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 });
          if (error) throw error;
          users.push(...data.users);
          if (data.users.length < 200) break;
        }
        const { data: profiles } = await admin.from("profiles").select("id, full_name, role, removed_at");
        const byId = new Map((profiles || []).map((p) => [p.id, p]));
        const now = Date.now();
        return json({
          me: me.id,
          team: users.map((u) => {
            const p = byId.get(u.id);
            const banned = !!u.banned_until && new Date(u.banned_until).getTime() > now;
            return {
              id: u.id,
              email: u.email,
              name: p?.full_name || "",
              role: p?.role || "none",
              status: p?.removed_at ? "removed" : banned ? "disabled" : (u.last_sign_in_at || u.email_confirmed_at) ? "active" : "invited",
              lastSignIn: u.last_sign_in_at,
              createdAt: u.created_at,
            };
          }),
        });
      }

      case "add": {
        const email = String(body.email || "").trim().toLowerCase();
        const name = String(body.name || "").trim();
        const role = String(body.role || "staff");
        const password = typeof body.password === "string" ? body.password : "";
        if (!EMAIL.test(email)) return fail("Enter a valid email address.");
        if (!ROLES.includes(role)) return fail("Pick Owner or Staff.");
        let id: string;
        if (password) {
          if (password.length < 8) return fail("The password needs at least 8 characters.");
          const { data, error } = await admin.auth.admin.createUser({
            email, password, email_confirm: true, user_metadata: { full_name: name },
          });
          if (error) return fail(/already|registered|exists/i.test(error.message) ? "Someone with that email is already on the team." : error.message);
          id = data.user.id;
        } else {
          const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { data: { full_name: name }, redirectTo });
          if (error) return fail(/already|registered|exists/i.test(error.message) ? "Someone with that email is already on the team." : /rate/i.test(error.message) ? "Too many emails sent recently. Wait an hour, or set a password instead." : error.message);
          id = data.user.id;
        }
        await setProfile(id, { full_name: name || email.split("@")[0], role });
        await log("add", id, { email, role, detail: `${name || email} added as ${role}${password ? " with a password set by the owner" : " by invitation email"}` });
        return json({ ok: true, id });
      }

      case "setRole": {
        const role = String(body.role || "");
        if (!ROLES.includes(role)) return fail("Pick Owner or Staff.");
        if (role === "staff") { const g = await guardTarget("make staff"); if (g) return fail(g); }
        else if (!userId) return fail("Choose a person.");
        await setProfile(userId, { role });
        await log("role", userId, { email: await emailOf(userId), detail: `Role changed to ${role}` });
        return json({ ok: true });
      }

      case "rename": {
        const name = String(body.name || "").trim();
        if (!userId || !name) return fail("Enter a name.");
        await setProfile(userId, { full_name: name });
        return json({ ok: true });
      }

      case "setPassword": {
        const password = String(body.password || "");
        if (!userId) return fail("Choose a person.");
        if (password.length < 8) return fail("The password needs at least 8 characters.");
        const { error } = await admin.auth.admin.updateUserById(userId, { password });
        if (error) return fail(error.message);
        await log("password", userId, { email: await emailOf(userId), detail: "Password set by an owner" });
        return json({ ok: true });
      }

      case "sendReset": {
        if (!userId) return fail("Choose a person.");
        const { data: u, error: ue } = await admin.auth.admin.getUserById(userId);
        if (ue || !u?.user?.email) return fail("That person has no email address.");
        const { error } = await admin.auth.resetPasswordForEmail(u.user.email, { redirectTo });
        if (error) return fail(/rate/i.test(error.message) ? "Too many emails sent recently. Wait an hour, or set a password instead." : error.message);
        await log("reset_email", userId, { email: u.user.email, detail: "Password reset link emailed" });
        return json({ ok: true, email: u.user.email });
      }

      case "setDisabled": {
        const disabled = body.disabled === true;
        if (disabled) { const g = await guardTarget("disable"); if (g) return fail(g); }
        else if (!userId) return fail("Choose a person.");
        const { error } = await admin.auth.admin.updateUserById(userId, { ban_duration: disabled ? FOREVER : "none" });
        if (error) return fail(error.message);
        if (!disabled) await setProfile(userId, { removed_at: null });
        await log(disabled ? "disable" : "enable", userId, { email: await emailOf(userId), detail: disabled ? "Sign-in disabled" : "Sign-in allowed again" });
        return json({ ok: true });
      }

      // Logins are never deleted (so nothing is lost and it can be undone): "remove" blocks
      // sign-in for good and marks the person as removed. "Allow sign-in again" undoes it.
      case "remove": {
        const g = await guardTarget("remove");
        if (g) return fail(g);
        const { error } = await admin.auth.admin.updateUserById(userId, { ban_duration: FOREVER });
        if (error) return fail(error.message);
        await setProfile(userId, { removed_at: new Date().toISOString() });
        await log("remove", userId, { email: await emailOf(userId), detail: "Removed from the team (login blocked, nothing deleted)" });
        return json({ ok: true });
      }

      default:
        return fail("Unknown action.");
    }
  } catch (e) {
    console.error("team-admin", action, e);
    return fail("Something went wrong on the server. Try again.", 500);
  }
});
