# Where Stayover Mikocheni keeps data

Checked on 25 Nov 2026 against the live project. "Backed up" means it is in the nightly encrypted backup.

| # | What | Where it lives | How much (25 Nov 2026) | Backed up | Notes |
|---|---|---|---|---|---|
| 1 | Bookings (guests, dates, amounts, fees, LUKU readings, ID numbers) | Supabase database → `public.bookings` | 8 | ✅ nightly | Deletes are soft: kept 30 days, then cleared by the backup job |
| 2 | Money in & out (expenses, LUKU purchases, other income) | `public.transactions` | 11 | ✅ | Soft delete, 30 days |
| 3 | Recurring cost templates | `public.recurring` | 0 | ✅ | Soft delete, 30 days |
| 4 | Team members and roles | `public.profiles` | 2 | ✅ | Never deleted: "Remove" blocks the login |
| 5 | Logins (email, password hash, sign-in history) | Supabase Auth → `auth.users` + related auth tables | 2 | ✅ | Restored logins keep their passwords |
| 6 | Change log (who changed or deleted what) | `public.audit_log` | grows | ✅ | Nobody can edit or erase it |
| 7 | Removed ID files waiting 30 days | `public.file_trash` | 0 | ✅ | |
| 8 | Guest ID photos and PDFs | Supabase Storage, private bucket `guest-ids` | 0 files | ✅ files downloaded nightly | The database only holds the list; the files themselves are copied separately |
| 9 | Safety copy taken before the 25 Nov changes | `safety.*_20261125` tables in the same database | copies of 1–4 + file list | ✅ | Not reachable from the app or API. Can be dropped once two good nightly backups exist |
| 10 | Database structure, security rules, triggers | Supabase database + `supabase/` folder in GitHub | — | ✅ both | Rules on Supabase's own auth/storage are re-applied by `supabase/after-restore.sql` |
| 11 | Team server function | Supabase Edge Function `team-admin` | — | Code in GitHub | Redeploy from `supabase/functions/team-admin` |
| 12 | The app itself (`index.html`, `config.js`) | GitHub `gadxan/stayovers` → Vercel | — | GitHub is the copy | Vercel rebuilds from GitHub |
| 13 | Settings (Supabase auth, Vercel, GitHub secrets, B2) | Each provider's dashboard | — | Written down in `docs/SETTINGS.md` | Secrets themselves are not written down anywhere in the repo |
| 14 | Old claude.ai version of the app | claude.ai artifact database | 1 entry (8 Nov LUKU purchase) | ❌ | Legacy. Re-enter the entry, then stop using that page |
| 15 | Things on staff phones / browsers | Browser memory only while the page is open | — | n/a | The app stores nothing permanently on devices (no local storage) |
| 16 | Excel exports people download | Wherever they save them | — | n/a | These are copies, not the source |

Nothing else stores Stayover data: there are no other databases, spreadsheets or servers.
