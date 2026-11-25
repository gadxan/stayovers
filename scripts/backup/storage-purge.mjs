// Removes ID files whose booking (or removal) is more than 30 days old. The list comes from
// public.purge_deleted(30), which the nightly job runs only after the backup is safely stored.
// Usage: SUPABASE_URL=... SUPABASE_SECRET_KEY=... node scripts/backup/storage-purge.mjs <listFile>
import { readFile } from "node:fs/promises";

const base = (process.env.SUPABASE_URL || "").replace(/\/$/, "");
const key = process.env.SUPABASE_SECRET_KEY || "";
const paths = (await readFile(process.argv[2], "utf8")).split("\n").map(s => s.trim()).filter(Boolean);
if (!paths.length) { console.log("No files due for removal."); process.exit(0); }
const headers = { apikey: key, "Content-Type": "application/json" };
if (key.startsWith("eyJ")) headers.Authorization = `Bearer ${key}`;
for (let i = 0; i < paths.length; i += 100) {
  const r = await fetch(`${base}/storage/v1/object/guest-ids`, { method: "DELETE", headers, body: JSON.stringify({ prefixes: paths.slice(i, i + 100) }) });
  if (!r.ok) throw new Error(`Removing old files failed: HTTP ${r.status}`);
}
console.log(`Removed ${paths.length} file(s) deleted more than 30 days ago.`);
