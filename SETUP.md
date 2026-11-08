# Stayover Mikocheni: setup on your own website

This folder is the full app. It runs as a website you host, with your records in your own **Supabase** database (a hosted Postgres database with logins and file storage).

| File | What it is |
|---|---|
| `index.html` | The app: overview, calendar, bookings, profit & loss, electricity, recurring costs, Excel export |
| `config.js` | Your Supabase address and public key (you fill this in) |
| `supabase/schema.sql` | Creates the tables, the owner/staff roles, the security rules and the private ID-file storage |
| `_headers` | Security settings used by Netlify when you host there |

## Who can do what

| | Owner | Staff |
|---|---|---|
| Calendar, bookings, guest IDs, meter readings | ✓ | ✓ |
| Delete a booking | ✓ | – |
| Record expenses and LUKU purchases | ✓ | ✓ (sees only their own) |
| Overview, profit & loss, electricity report, recurring costs | ✓ | – |
| Export to Excel | ✓ | – |

These rules are enforced inside the database, not just hidden in the app. A staff member who tries to read the profit figures directly gets nothing back.

---

## 1. Create the Supabase project (about 10 minutes)

1. Go to **supabase.com**, sign up, and click **New project**.
2. Name it `stayover-mikocheni`, set a strong database password (save it in a password manager), and pick the region closest to Dar es Salaam from the list.
3. Wait for the project to finish setting up.

## 2. Create the tables and security rules

1. In the project, open **SQL Editor → New query**.
2. Open `supabase/schema.sql`, copy everything, paste it in, and click **Run**. It should say *Success. No rows returned*.

## 3. Lock down sign-ups

Go to **Authentication** and:

1. Under **Sign In / Providers → Email**, keep Email turned on and **turn off "Allow new users to sign up"**. Then only people you add can get in.
2. Under **URL Configuration**, set **Site URL** to your website address (you'll get this in step 6; come back and set it then). Add the same address under **Redirect URLs**.

## 4. Create your owner login

1. **Authentication → Users → Add user → Create new user**. Enter your email and a password, and tick **Auto Confirm User**.
2. In **SQL Editor**, run this with your email:

   ```sql
   update public.profiles set role = 'owner'
   where id = (select id from auth.users where email = 'you@example.com');
   ```

Repeat for a business partner who should also see the money.

## 5. Connect the app

1. Open **Project Settings → API Keys** (on some projects it's **Settings → API**).
2. Copy the **Project URL** and the **publishable** key (`sb_publishable_…`), or on older projects the **anon public** key.
3. Paste them into `config.js`:

   ```js
   window.STAYOVER_CONFIG = {
     supabaseUrl: "https://abcdxyz.supabase.co",
     supabaseAnonKey: "eyJhbGciOi..."
   };
   ```

The public key is designed to be visible in the browser; the security rules protect the data. **Never** put the `service_role` or `secret` key in this file.

## 6. Put it online (free with Netlify)

1. Go to **app.netlify.com/drop** (create a free account).
2. Drag the whole `stayover-mikocheni-web` folder onto the page. You get an address like `https://stayover-mikocheni.netlify.app`. You can rename it under **Site configuration → Change site name**.
3. Go back to Supabase step 3.2 and put this address in **Site URL** and **Redirect URLs**.
4. Optional: add your own domain under **Domain management**. HTTPS is set up automatically. Then add that domain in Supabase too.

To update the site later, drag the folder onto **Deploys** in your Netlify site.

## 7. Add your staff

**Authentication → Users → Invite user** and enter their email. They get an email, tap the link, and the app asks them to choose a password. New people are **staff** automatically.

To remove someone, delete them under **Authentication → Users**. They lose access immediately.

Supabase's built-in email service only sends a few emails per hour. That's enough for a small team. If invites or "Forgot password" emails stop arriving, wait an hour, or connect your own email under **Authentication → Emails → SMTP Settings**.

## 8. Your existing records

Your records on the claude.ai page don't move over automatically. So far that's one LUKU purchase (8 Nov 2026, Bottom unit, 144 kWh, TSh 50,000): add it again with **+ Expense**.

---

## Keeping the data safe

**What protects it**
- Only people you add can sign in. Public sign-up is off.
- Every table has row-level security. Staff can't read profit & loss or other people's expenses, even with technical tricks.
- Guest ID files are in a **private** bucket. The app opens them through links that expire after 10 minutes, so a copied link stops working.
- Traffic is encrypted (HTTPS), and the `_headers` file tells browsers not to embed the site, not to let search engines index it, and only to talk to Supabase.

**What you need to do**
1. **Back up monthly.** Use **Export to Excel** in Year view at the end of each month and keep the file somewhere safe. On Supabase's free plan, download backups aren't included (check their current pricing; the paid plan adds daily backups).
2. **Keep the project active.** Supabase pauses free projects after a period with no use. Normal daily use prevents this. If it pauses, you can restore it from the dashboard.
3. **Use strong passwords** and turn on two-factor sign-in for your Supabase and Netlify accounts. Whoever controls those accounts controls the data.
4. **Remove leavers the same day.**
5. **Guest ID rules.** Tanzania's Personal Data Protection Act (2022) covers copies of passports and IDs. Check with the Personal Data Protection Commission whether you need to register. Keep IDs only as long as you need them. Delete a booking's ID files once you no longer need them: open the booking, tap ✕ on each file, then **Save changes**.

## Troubleshooting

| You see | Fix |
|---|---|
| "Not connected yet: add your Supabase address…" | `config.js` still has the placeholder values (step 5) |
| "This login isn't on the Stayover team yet" | The user was created before you ran `schema.sql`. In SQL Editor run `insert into public.profiles (id) select id from auth.users on conflict do nothing;` |
| Sign-in link opens a page that says "invalid" | The Site URL / Redirect URLs in step 3.2 don't match your website address |
| Staff can't see Overview or Profit & loss | That's intended; make them owner in step 4.2 if they should |
