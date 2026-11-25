-- Stayover Mikocheni — 30-day undo for deletes, and a log of who changed or deleted what.
-- Reverse with: 20261125120000_soft_delete_and_audit.down.sql
--
-- What changes:
--  * Bookings, money entries and recurring costs get deleted_at / deleted_by.
--    "Delete" in the app now only sets deleted_at; the row stays for 30 days and can be restored.
--  * Nobody can hard-delete those rows through the app or the API any more (delete policies removed).
--    The nightly backup job calls purge_deleted(30) to remove rows deleted more than 30 days ago.
--  * ID photos removed from a booking go to file_trash and are kept 30 days too.
--  * audit_log records every create, edit, delete, restore and purge, with who did it and the
--    before/after values. Only owners can read it; nobody can edit or delete it.
--  * Team members are never deleted: "Remove" disables the login and sets profiles.removed_at.

begin;

-- ---------- soft delete columns ----------
alter table public.bookings     add column if not exists deleted_at timestamptz, add column if not exists deleted_by uuid;
alter table public.transactions add column if not exists deleted_at timestamptz, add column if not exists deleted_by uuid;
alter table public.recurring    add column if not exists deleted_at timestamptz, add column if not exists deleted_by uuid;
alter table public.profiles     add column if not exists removed_at timestamptz;

-- Only owners may delete/restore bookings and recurring costs; staff may delete their own
-- money entries (the update policy already limits them to their own rows).
create or replace function public.guard_soft_delete()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.deleted_at is distinct from old.deleted_at then
    if auth.uid() is not null and tg_table_name in ('bookings', 'recurring') and not public.is_owner() then
      raise exception 'Only owners can delete or restore this.' using errcode = '42501';
    end if;
    if old.deleted_at is null and new.deleted_at is not null then
      new.deleted_at := now();
      new.deleted_by := auth.uid();
    elsif new.deleted_at is null then
      new.deleted_by := null;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists bookings_guard_delete on public.bookings;
drop trigger if exists transactions_guard_delete on public.transactions;
drop trigger if exists recurring_guard_delete on public.recurring;
create trigger bookings_guard_delete before update on public.bookings for each row execute function public.guard_soft_delete();
create trigger transactions_guard_delete before update on public.transactions for each row execute function public.guard_soft_delete();
create trigger recurring_guard_delete before update on public.recurring for each row execute function public.guard_soft_delete();

-- No hard deletes through the API.
drop policy if exists "bookings: owner deletes" on public.bookings;
drop policy if exists "transactions: owner or own delete" on public.transactions;
drop policy if exists "recurring: owner all" on public.recurring;
create policy "recurring: owner reads" on public.recurring for select to authenticated using (public.is_owner());
create policy "recurring: owner adds" on public.recurring for insert to authenticated with check (public.is_owner());
create policy "recurring: owner edits" on public.recurring for update to authenticated using (public.is_owner()) with check (public.is_owner());
revoke delete on public.bookings, public.transactions, public.recurring from anon, authenticated;

-- ---------- removed ID files wait here for 30 days ----------
create table if not exists public.file_trash (
  path text primary key,
  booking_id text,
  removed_at timestamptz not null default now(),
  removed_by uuid default auth.uid()
);
alter table public.file_trash enable row level security;
drop policy if exists "file_trash: members add" on public.file_trash;
drop policy if exists "file_trash: owner reads" on public.file_trash;
create policy "file_trash: members add" on public.file_trash for insert to authenticated with check (public.is_member());
create policy "file_trash: owner reads" on public.file_trash for select to authenticated using (public.is_owner());
revoke all on public.file_trash from anon;
revoke update, delete on public.file_trash from authenticated;

-- Uploaders may no longer delete ID files themselves; only owners can (the app never needs to).
drop policy if exists "guest ids: owner or uploader deletes" on storage.objects;
create policy "guest ids: owner deletes" on storage.objects
  for delete to authenticated using (bucket_id = 'guest-ids' and public.is_owner());

-- ---------- change log ----------
create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor uuid,
  actor_email text,
  table_name text not null,
  row_id text,
  action text not null,
  old_data jsonb,
  new_data jsonb
);
create index if not exists audit_log_at on public.audit_log (at desc);
create index if not exists audit_log_row on public.audit_log (table_name, row_id);
alter table public.audit_log enable row level security;
drop policy if exists "audit_log: owner reads" on public.audit_log;
create policy "audit_log: owner reads" on public.audit_log for select to authenticated using (public.is_owner());
revoke all on public.audit_log from anon;
revoke insert, update, delete, truncate on public.audit_log from authenticated;

create or replace function public.audit_row()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  o jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  n jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  act text;
  who text;
begin
  if tg_op = 'INSERT' then act := 'create';
  elsif tg_op = 'DELETE' then act := 'purge';
  elsif (o->>'deleted_at') is null and (n->>'deleted_at') is not null then act := 'delete';
  elsif (o->>'deleted_at') is not null and (n->>'deleted_at') is null then act := 'restore';
  elsif (o->>'removed_at') is null and (n->>'removed_at') is not null then act := 'remove';
  else act := 'edit';
  end if;
  if tg_op = 'UPDATE' and o - 'updated_at' = n - 'updated_at' then
    return new; -- nothing really changed
  end if;
  select email into who from auth.users where id = auth.uid();
  insert into public.audit_log (actor, actor_email, table_name, row_id, action, old_data, new_data)
  values (auth.uid(), who, tg_table_name, coalesce(n->>'id', o->>'id'), act, o, n);
  return coalesce(new, old);
end;
$$;

drop trigger if exists bookings_audit on public.bookings;
drop trigger if exists transactions_audit on public.transactions;
drop trigger if exists recurring_audit on public.recurring;
drop trigger if exists profiles_audit on public.profiles;
create trigger bookings_audit after insert or update or delete on public.bookings for each row execute function public.audit_row();
create trigger transactions_audit after insert or update or delete on public.transactions for each row execute function public.audit_row();
create trigger recurring_audit after insert or update or delete on public.recurring for each row execute function public.audit_row();
create trigger profiles_audit after insert or update or delete on public.profiles for each row execute function public.audit_row();

-- ---------- the 30-day clean-up (run by the nightly backup job, never by the app) ----------
create or replace function public.purge_deleted(keep_days int default 30)
returns table (file_path text) language plpgsql security definer set search_path = public as $$
declare cutoff timestamptz := now() - make_interval(days => greatest(keep_days, 30));
begin
  return query
    with gone as (delete from public.bookings where deleted_at < cutoff returning data)
    select d->>'path' from gone g,
      jsonb_array_elements(coalesce(g.data->'idDocs', '[]'::jsonb)) d
    where d ? 'path';
  delete from public.transactions where deleted_at < cutoff;
  delete from public.recurring where deleted_at < cutoff;
  return query delete from public.file_trash where removed_at < cutoff returning path;
end;
$$;
revoke all on function public.purge_deleted(int) from public, anon, authenticated;
revoke all on function public.guard_soft_delete() from public, anon, authenticated;
revoke all on function public.audit_row() from public, anon, authenticated;

commit;
