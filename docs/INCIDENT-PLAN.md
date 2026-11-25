# When data goes missing: 1-page plan

**Stay calm. Don't delete, re-enter or "fix" anything until step 3.** Most problems can be undone if nothing else gets overwritten.

### 1. What kind of problem is it? (5 minutes)
| You see | Most likely | Go to |
|---|---|---|
| One or a few bookings/entries gone | Someone deleted them | **A** |
| Numbers changed and you don't know why | Someone edited | **B** |
| App won't load / "Couldn't reach" for everyone | Supabase paused or down | **C** |
| Lots of data gone or wrong, or a stranger had access | Serious incident | **D** |

### A. Something was deleted (fixable in 1 minute, within 30 days)
History tab → **Recently deleted** → **Restore**. History → **Change log** shows who deleted it and when.

### B. Something was changed
History → **Change log** → filter Bookings or Money. Each change shows old → new values and who made it. Type the old value back in.

### C. App down for everyone
1. Open supabase.com/dashboard. If the project says **Paused**, click **Restore project** (2–5 minutes). Nothing is lost.
2. If Supabase shows an outage (status.supabase.com), wait. Record bookings on paper meanwhile.

### D. Serious incident (data lost, corrupted or someone broke in)
1. **Lock out**: change the owner's passwords (Supabase, GitHub, email). In the app: Team → disable anyone suspicious. In Supabase → API Keys → create a new secret key and delete the old one, then update the GitHub secret `SUPABASE_SECRET_KEY`.
2. **Freeze**: tell staff to stop using the app; record on paper.
3. **Pick a backup**: Backblaze B2 → your bucket → `daily/`. Choose the last backup **before** the problem (one per night, kept 90 days, can't be deleted for 30 days).
4. **Restore into a NEW Supabase project, never over the live one first** (docs/BACKUPS.md → "Restoring"):
   `./scripts/restore.sh stayover-<date>.tar.gz.cms "<new project DB URL>" <new project URL> <new secret key>`
   It needs the **private backup key** from your password manager. It checks every table and file and prints how long it took.
5. **Check** the new project in the app (temporarily point `config.js` at it), then either switch the app to it for good or copy the missing records back.
6. **Afterwards**: write down what happened, when, what was lost, what you changed. Run a restore drill (GitHub → Actions → Restore drill).

### Who to call
- Owner: decides and holds the backup key.
- Help: Supabase support (dashboard → Support), Backblaze support, or any developer, with this page and docs/BACKUPS.md.

### Numbers to know
Daily backup at **00:15 Dar es Salaam time**: at most about one day of data at risk. Deleted items: **30 days** to restore. Backups kept **90 days**, undeletable for **30 days**. Last drill: see GitHub → Actions → Restore drill.
