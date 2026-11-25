# Backups for Stayover Mikocheni

## How it works
Every night at **00:15 Dar es Salaam time**, GitHub runs `.github/workflows/backup.yml`:

1. Dumps the whole database (logins, bookings, money, team, change log) and downloads every guest-ID file.
2. Checks the dump against the live row counts. Nothing missing, or it fails.
3. Seals the contents with checksums and **encrypts** them with your public key.
4. Uploads them to **Backblaze B2** with a write-only key. B2's Object Lock keeps each backup **undeletable for 30 days**, even with your own master key. Backups are kept 90 days.
5. Restores the backup into a **throwaway test copy** (a temporary Supabase started inside GitHub), compares every table and every file, and records how long it took.
6. Only then clears items deleted more than 30 days ago.

If any step fails, GitHub emails you, and Healthchecks.io (optional) alerts you if a backup doesn't run at all. Every Sunday, `.github/workflows/restore-drill.yml` waits for your approval. It then downloads the latest backup from B2, decrypts it with your private key, restores it into a throwaway copy, checks everything and reports the time.

The test copy is created and destroyed inside GitHub on every run. It is completely separate from your real database, and tests and drills never write to the real one.

## One-time setup (about 30 minutes)

### Step 1: Make the backup key (on this Mac, 2 minutes)
In Terminal, in the project folder, run:
```bash
./scripts/make-backup-key.sh
```
It shows the **private key** once. Copy everything, including the BEGIN/END lines, into your password manager as a secure note named **Stayover backup private key**. Keep a second copy too, printed or in a second password manager. Press Enter and it is erased from the Mac. The **public** key stays in `backup/backup-public-cert.pem`. Tell Claude to push it, or run `git add backup && git commit -m "Add backup public key" && git push`.

> Without the private key nobody, including you, can open a backup. If you lose it, make a new pair; older backups stay locked.

### Step 2: Backblaze B2 (15 minutes)
1. Sign up at **backblaze.com → B2 Cloud Storage** (first 10 GB free). Turn on two-factor sign-in.
2. **Buckets → Create a Bucket**: name e.g. `stayover-backups-<something-random>`, Files: **Private**, Encryption: **Enable**, **Object Lock: Enable**. Then open the bucket's Object Lock settings: **Default retention: Compliance, 30 days**.
3. On the bucket, **Lifecycle Settings → Use custom lifecycle rules**: file name prefix `daily/`, "Days till hide" **90**, "Days till delete" **1**.
4. **Application Keys → Add a New Application Key**, twice:
   - Name `stayover-backup-writer`, bucket: your bucket, **Type of Access: Write Only**.
   - Name `stayover-drill-reader`, bucket: your bucket, **Type of Access: Read Only**.
   Each time, copy the **keyID** and **applicationKey** straight into GitHub (step 4). B2 shows them only once.

### Step 3: Supabase values (5 minutes)
1. Supabase → your project → **Connect** → **Session pooler** → copy the connection string, and put your database password in place of `[YOUR-PASSWORD]`. If you don't know it: Database → Settings → Reset database password.
2. Supabase → **Project Settings → API Keys** → **Secret keys** → create one named `github-backup` and copy it.

### Step 4: GitHub secrets (5 minutes)
github.com/gadxan/stayovers → **Settings → Secrets and variables → Actions → New repository secret**, one at a time:

| Name | Value |
|---|---|
| `PROD_DB_URL` | the session pooler connection string with password |
| `SUPABASE_URL` | `https://ajanwxumictvchwrarhh.supabase.co` |
| `SUPABASE_SECRET_KEY` | the `github-backup` secret key |
| `B2_BUCKET` | your bucket name |
| `B2_KEY_ID` / `B2_KEY` | keyID / applicationKey of **stayover-backup-writer** |
| `B2_READ_KEY_ID` / `B2_READ_KEY` | keyID / applicationKey of **stayover-drill-reader** |

Then **Settings → Environments → New environment** `restore-drill`: tick **Required reviewers** and add yourself. Add an environment secret `BACKUP_PRIVATE_KEY` and paste the private key from your password manager. This lets the weekly drill decrypt backups, but only after you approve each run. Leave it out if you'd rather keep the key only in your password manager. You can then run drills by hand with `scripts/restore.sh`.

### Step 5 (optional, recommended): missed-backup alarm
Sign up free at **healthchecks.io**. Add a check with **Period 1 day, Grace 2 hours**, and copy its ping URL into a GitHub secret `HEALTHCHECK_URL`. It emails you if a night passes with no successful backup, even if GitHub itself never ran the job.

### Step 6: First run
GitHub → **Actions → Nightly backup → Run workflow**. A green tick means it worked. Then **Actions → Restore drill → Run workflow** and approve it. The run page shows the drill report: rows, files and seconds.

## Restoring

### Something was deleted in the last 30 days
App → **History → Recently deleted → Restore**. No backup needed.

### Restore a backup (one command)
You need, once: **Postgres.app** (postgresapp.com; it provides `psql`) and **Node.js**.
1. Download the backup file from Backblaze (bucket → `daily/` → the date you want → Download).
2. Create a **new, empty** Supabase project to restore into. Never restore over the live one first.
3. Run:
```bash
./scripts/restore.sh ~/Downloads/stayover-<date>.tar.gz.cms "<new project session pooler URL>" https://<new-ref>.supabase.co <new project secret key>
```
It asks for the private key (paste, then Ctrl-D). It decrypts, checks the seal, restores the database and the ID files, compares every table and file with the backup, and prints the time taken. It refuses to touch the live project unless you type `RESTORE OVER LIVE DATA`.
4. In the new project: deploy the `team-admin` function, set Auth → URL Configuration and turn off sign-ups (docs/SETTINGS.md). Then point `config.js` at it.

## Database changes (migrations)
Every change is a file in `supabase/migrations/` with a matching undo file in `supabase/rollbacks/`. Before applying one to the live database, take a backup: GitHub → Actions → Nightly backup → Run workflow, or for small changes a safety copy inside the database (`create table safety.<name>_<date> as table …`).
