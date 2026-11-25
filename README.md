# Stayover Mikocheni

Income and operations tracker for two short-stay units (Bottom and Top) in Mikocheni, Dar es Salaam.

- Bookings with guest ID uploads, booking source (Airbnb, Instagram, agents, referrals) and LUKU meter readings
- Occupancy calendar
- Profit & loss by unit, with daily, weekly, monthly and yearly reports
- Electricity: tokens bought, price per kWh, usage per guest
- Recurring and one-off expenses
- Export to Excel
- Owner and staff roles, enforced in the database
- Team page for owners: add people, change roles, reset passwords, disable or remove access (server function in `supabase/functions/team-admin`)

Runs as a static website (`index.html`) on a [Supabase](https://supabase.com) backend. See **[SETUP.md](SETUP.md)** to set it up and host it.

Data safety: nightly encrypted off-site backups with an automatic test restore, 30-day undo for deletes, and a change log. See **[docs/BACKUPS.md](docs/BACKUPS.md)**, [docs/DATA-MAP.md](docs/DATA-MAP.md), [docs/SETTINGS.md](docs/SETTINGS.md) and the 1-page [docs/INCIDENT-PLAN.md](docs/INCIDENT-PLAN.md).

`config.js` only ever holds the public Supabase key. Never commit a `service_role` or secret key.
