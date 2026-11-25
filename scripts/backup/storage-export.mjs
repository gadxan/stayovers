// Downloads every guest-ID file from Supabase Storage into a folder and writes a manifest
// (path, size, sha256) next to it. Never prints file contents or names of guests.
// Usage: SUPABASE_URL=... SUPABASE_SECRET_KEY=... node scripts/backup/storage-export.mjs <outDir>
import { mkdir, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";

const BUCKET = process.env.BUCKET || "guest-ids";
const base = (process.env.SUPABASE_URL || "").replace(/\/$/, "");
const key = process.env.SUPABASE_SECRET_KEY || "";
const out = process.argv[2];
if (!base || !key || !out) { console.error("Need SUPABASE_URL, SUPABASE_SECRET_KEY and an output folder."); process.exit(2); }

const headers = { apikey: key };
if (key.startsWith("eyJ")) headers.Authorization = `Bearer ${key}`; // legacy service_role key

async function list(prefix) {
  const found = [];
  for (let offset = 0; ; offset += 1000) {
    const r = await fetch(`${base}/storage/v1/object/list/${BUCKET}`, {
      method: "POST", headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify({ prefix, limit: 1000, offset, sortBy: { column: "name", order: "asc" } }),
    });
    if (!r.ok) throw new Error(`Listing ${BUCKET} failed: HTTP ${r.status}`);
    const items = await r.json();
    for (const it of items) {
      const p = prefix ? `${prefix}/${it.name}` : it.name;
      if (it.id === null || it.id === undefined) found.push(...await list(p)); // a folder
      else found.push({ path: p, contentType: it.metadata?.mimetype || "application/octet-stream" });
    }
    if (items.length < 1000) break;
  }
  return found;
}

const files = await list("");
const manifest = [];
for (const f of files) {
  const r = await fetch(`${base}/storage/v1/object/${BUCKET}/${f.path.split("/").map(encodeURIComponent).join("/")}`, { headers });
  if (!r.ok) throw new Error(`Download failed (HTTP ${r.status}) for file ${manifest.length + 1} of ${files.length}`);
  const buf = Buffer.from(await r.arrayBuffer());
  const dest = path.resolve(out, f.path);
  if (!dest.startsWith(path.resolve(out) + path.sep)) throw new Error("Unsafe file path in bucket");
  await mkdir(path.dirname(dest), { recursive: true });
  await writeFile(dest, buf);
  manifest.push({ path: f.path, size: buf.length, sha256: createHash("sha256").update(buf).digest("hex"), contentType: f.contentType });
}
await writeFile(path.join(out, "..", "files-manifest.json"), JSON.stringify({ bucket: BUCKET, count: manifest.length, files: manifest }, null, 1));
console.log(`Exported ${manifest.length} file(s), ${manifest.reduce((a, f) => a + f.size, 0)} bytes.`);
