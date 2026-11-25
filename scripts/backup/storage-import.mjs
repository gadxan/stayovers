// Uploads the guest-ID files from a backup into a Supabase project (the test copy, or a
// replacement project after a disaster) and checks each one against the manifest.
// Usage: TARGET_URL=... TARGET_KEY=... node scripts/backup/storage-import.mjs <backupDir>
//   <backupDir> holds files/ and files-manifest.json
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";

const base = (process.env.TARGET_URL || "").replace(/\/$/, "");
const key = process.env.TARGET_KEY || "";
const dir = process.argv[2];
if (!base || !key || !dir) { console.error("Need TARGET_URL, TARGET_KEY and the backup folder."); process.exit(2); }
const headers = { apikey: key };
if (key.startsWith("eyJ")) headers.Authorization = `Bearer ${key}`;

const m = JSON.parse(await readFile(path.join(dir, "files-manifest.json"), "utf8"));
let ok = 0;
for (const f of m.files) {
  const buf = await readFile(path.join(dir, "files", f.path));
  if (createHash("sha256").update(buf).digest("hex") !== f.sha256) throw new Error(`A file in the backup is damaged (file ${ok + 1})`);
  const url = `${base}/storage/v1/object/${m.bucket}/${f.path.split("/").map(encodeURIComponent).join("/")}`;
  const r = await fetch(url, { method: "POST", headers: { ...headers, "Content-Type": f.contentType, "x-upsert": "true" }, body: buf });
  if (!r.ok) throw new Error(`Upload failed (HTTP ${r.status}) for file ${ok + 1} of ${m.count}`);
  // read it back and compare
  const back = Buffer.from(await (await fetch(url, { headers })).arrayBuffer());
  if (createHash("sha256").update(back).digest("hex") !== f.sha256) throw new Error(`File ${ok + 1} came back different after upload`);
  ok++;
}
console.log(`Restored and checked ${ok} of ${m.count} file(s).`);
if (ok !== m.count) process.exit(1);
