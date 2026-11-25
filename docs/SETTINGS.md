# Every setting Stayover Mikocheni needs to run

Use this to rebuild everything from nothing. **Secret values are never written here.** Where a value is secret, it says where it is kept.

## 1. The app (`config.js`, in GitHub)
| Setting | Value |
|---|---|
| `supabaseUrl` | `https://ajanwxumictvchwrarhh.supabase.co` |
| `supabaseAnonKey` | the project's **publishable** key (`sb_publishable_…`). Public by design. |

## 2. Supabase project
| Setting | Value / where |
|---|---|
| Project | "gadxan's Project", ref `ajanwxumictvchwrarhh`, region eu-west-2 (London), Postgres 17, **Free plan** |
| Database structure | `supabase/schema.sql`, then every file in `supabase/migrations/` in date order |
| After a restore into a new project | run `supabase/after-restore.sql` |
| Edge Function | `team-admin` from `supabase/functions/team-admin`, **verify JWT = off** (it checks the owner itself) |
| Auth → Email | Email sign-in on; **"Allow new users to sign up" = off** |
| Auth → URL Configuration | Site URL and Redirect URLs = the Vercel address (and any custom domain) |
| Storage | private bucket `guest-ids`, 20 MB limit, JPG/PNG/WEBP/HEIC/PDF (created by the SQL above) |
| Database password | known only to the owner; stored in the password manager and as GitHub secret `PROD_DB_URL` |
| Secret key (`sb_secret_…`) | Supabase dashboard → API Keys; also GitHub secret `SUPABASE_SECRET_KEY`. Never in the app |
| Point-in-time recovery | **Off** (needs Pro ≈ $130–140/month in total). Decision 25 Nov 2026 |
| Free-plan pausing | Supabase pauses free projects after ~7 days without use. The nightly backup job uses the database every day, which keeps it awake |

## 3. Vercel (website)
| Setting | Value |
|---|---|
| Git repository | `gadxan/stayovers`, branch `main`, deploys on every push |
| Framework | Other · Build command: none · Output directory: `.` |
| Security headers | `vercel.json` (in the repo) |
| Environment variables | none |

## 4. GitHub (`gadxan/stayovers`)
Repository → Settings → Secrets and variables → Actions:
| Secret | What |
|---|---|
| `PROD_DB_URL` | Supabase **Session pooler** connection string, with the database password |
| `SUPABASE_URL` | `https://ajanwxumictvchwrarhh.supabase.co` |
| `SUPABASE_SECRET_KEY` | Supabase secret key (`sb_secret_…`) |
| `B2_KEY_ID`, `B2_KEY` | Backblaze B2 **Write Only** key for this bucket (nightly backup: can add, can't read or delete) |
| `B2_READ_KEY_ID`, `B2_READ_KEY` | Backblaze B2 **Read Only** key for this bucket (restore drill: can download, can't change or delete) |
| `B2_BUCKET` | the B2 bucket name |
| `HEALTHCHECK_URL` | optional: Healthchecks.io ping URL for missed-backup alerts |

Environment `restore-drill` (Settings → Environments): secret `BACKUP_PRIVATE_KEY`, required reviewer = owner.
Notifications: GitHub → Settings → Notifications → Actions → "Send notifications for failed workflows only" (email).

## 5. Backblaze B2
| Setting | Value |
|---|---|
| Bucket | private, **Object Lock on**, default retention **Compliance, 30 days** |
| Lifecycle | keep files 90 days ("Keep prior versions for 90 days" / custom rule on `daily/`) |
| Application keys | two keys, both restricted to this bucket: **Write Only** (backup job) and **Read Only** (drill). Neither can delete. Object Lock also stops even the master key deleting a backup for 30 days |

## 6. Backup encryption
| Item | Where |
|---|---|
| Public key (locks backups) | `backup/backup-public-cert.pem` in GitHub |
| Private key (opens backups) | owner's password manager, note "Stayover backup private key" (+ paper copy). **Never on this computer, never in the repo** |

## 7. Accounts to keep safe (turn on two-factor sign-in for all)
GitHub `gadxan` · Supabase · Vercel · Backblaze · Healthchecks.io · the password manager · the email address these accounts use.
