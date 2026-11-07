-- Stayover Mikocheni — database, roles and security rules
-- Run this once in Supabase: Dashboard → SQL Editor → New query → paste → Run.
--
-- Two roles:
--   owner  sees and changes everything: profit & loss, all expenses, recurring costs, deleting bookings.
--   staff  sees the calendar and all bookings, adds and edits bookings (with guest IDs and meter readings),
--          and records expenses. Staff only see the expenses they entered themselves, never the full P&L.
-- Everyone who signs up starts as staff. Promote owners with the query at the bottom.

-- ---------- people ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'staff' check (role in ('owner', 'staff')),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_member()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid());
$$;

create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'owner');
$$;

-- ---------- records ----------
-- Each record keeps its fields in `data` (JSON), the same shape the app uses.
create table public.bookings (
  id text primary key,
  data jsonb not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.transactions (
  id text primary key,
  data jsonb not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.recurring (
  id text primary key,
  data jsonb not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- keep updated_at current and stop anyone rewriting who created a record
create or replace function public.touch_record()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.created_by := old.created_by;
  new.created_at := old.created_at;
  return new;
end;
$$;

create trigger bookings_touch before update on public.bookings for each row execute function public.touch_record();
create trigger transactions_touch before update on public.transactions for each row execute function public.touch_record();
create trigger recurring_touch before update on public.recurring for each row execute function public.touch_record();

-- signed-out visitors get nothing
revoke all on public.profiles, public.bookings, public.transactions, public.recurring from anon;

-- ---------- row level security ----------
alter table public.profiles enable row level security;
alter table public.bookings enable row level security;
alter table public.transactions enable row level security;
alter table public.recurring enable row level security;

-- profiles: you see yourself; owners see and manage the team
create policy "profiles: read own or owner" on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_owner());
create policy "profiles: owner updates" on public.profiles
  for update to authenticated using (public.is_owner()) with check (public.is_owner());

-- bookings: the whole team reads and writes; only owners delete
create policy "bookings: members read" on public.bookings
  for select to authenticated using (public.is_member());
create policy "bookings: members add" on public.bookings
  for insert to authenticated with check (public.is_member());
create policy "bookings: members edit" on public.bookings
  for update to authenticated using (public.is_member()) with check (public.is_member());
create policy "bookings: owner deletes" on public.bookings
  for delete to authenticated using (public.is_owner());

-- money in and out: owners see everything, staff only what they entered
create policy "transactions: owner or own read" on public.transactions
  for select to authenticated using (public.is_owner() or created_by = auth.uid());
create policy "transactions: members add own" on public.transactions
  for insert to authenticated with check (public.is_member() and (public.is_owner() or created_by = auth.uid()));
create policy "transactions: owner or own edit" on public.transactions
  for update to authenticated using (public.is_owner() or created_by = auth.uid())
  with check (public.is_owner() or created_by = auth.uid());
create policy "transactions: owner or own delete" on public.transactions
  for delete to authenticated using (public.is_owner() or created_by = auth.uid());

-- recurring costs: owners only
create policy "recurring: owner all" on public.recurring
  for all to authenticated using (public.is_owner()) with check (public.is_owner());

-- ---------- live updates between phones ----------
alter publication supabase_realtime add table public.bookings, public.transactions, public.recurring;

-- ---------- guest ID files (private bucket) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('guest-ids', 'guest-ids', false, 20971520,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'application/pdf'])
on conflict (id) do nothing;

create policy "guest ids: members upload" on storage.objects
  for insert to authenticated with check (bucket_id = 'guest-ids' and public.is_member());
create policy "guest ids: members view" on storage.objects
  for select to authenticated using (bucket_id = 'guest-ids' and public.is_member());
create policy "guest ids: owner or uploader deletes" on storage.objects
  for delete to authenticated using (bucket_id = 'guest-ids' and (public.is_owner() or owner_id = auth.uid()::text));

-- ---------- make yourself the owner ----------
-- After you have created your own login (see SETUP.md), run this with your email:
--   update public.profiles set role = 'owner'
--   where id = (select id from auth.users where email = 'you@example.com');
