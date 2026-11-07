# Stayover Mikocheni

Income and operations tracker for two short-stay units (Bottom and Top) in Mikocheni, Dar es Salaam.

- Bookings with guest ID uploads, booking source (Airbnb, Instagram, agents, referrals) and LUKU meter readings
- Occupancy calendar
- Profit & loss by unit, with daily, weekly, monthly and yearly reports
- Electricity: tokens bought, price per kWh, usage per guest
- Recurring and one-off expenses
- Export to Excel
- Owner and staff roles, enforced in the database

Runs as a static website (`index.html`) on a [Supabase](https://supabase.com) backend. See **[SETUP.md](SETUP.md)** to set it up and host it.

`config.js` only ever holds the public Supabase key. Never commit a `service_role` or secret key.
