-- Reverses 20261125120000_soft_delete_and_audit.sql.
-- WARNING: running this permanently removes rows that are currently in "Recently deleted",
-- and drops the change log. Back up first (the nightly job, or the safety snapshot below).
-- The app must be rolled back to the matching version at the same time.

begin;

-- keep a copy of the change log before dropping it
create schema if not exists safety;
create table if not exists safety.audit_log_before_down as table public.audit_log;

drop trigger if exists bookings_audit on public.bookings;
drop trigger if exists transactions_audit on public.transactions;
drop trigger if exists recurring_audit on public.recurring;
drop trigger if exists profiles_audit on public.profiles;
drop trigger if exists bookings_guard_delete on public.bookings;
drop trigger if exists transactions_guard_delete on public.transactions;
drop trigger if exists recurring_guard_delete on public.recurring;
drop function if exists public.purge_deleted(int);
drop function if exists public.audit_row();
drop function if exists public.guard_soft_delete();
drop table if exists public.audit_log;
drop table if exists public.file_trash;

-- soft-deleted rows would reappear in the old app, so remove them as the old app would have
delete from public.bookings where deleted_at is not null;
delete from public.transactions where deleted_at is not null;
delete from public.recurring where deleted_at is not null;
alter table public.bookings drop column if exists deleted_at, drop column if exists deleted_by;
alter table public.transactions drop column if exists deleted_at, drop column if exists deleted_by;
alter table public.recurring drop column if exists deleted_at, drop column if exists deleted_by;
alter table public.profiles drop column if exists removed_at;

-- original policies
drop policy if exists "recurring: owner reads" on public.recurring;
drop policy if exists "recurring: owner adds" on public.recurring;
drop policy if exists "recurring: owner edits" on public.recurring;
create policy "recurring: owner all" on public.recurring
  for all to authenticated using (public.is_owner()) with check (public.is_owner());
grant delete on public.bookings, public.transactions, public.recurring to authenticated;
create policy "bookings: owner deletes" on public.bookings
  for delete to authenticated using (public.is_owner());
create policy "transactions: owner or own delete" on public.transactions
  for delete to authenticated using (public.is_owner() or created_by = auth.uid());

drop policy if exists "guest ids: owner deletes" on storage.objects;
create policy "guest ids: owner or uploader deletes" on storage.objects
  for delete to authenticated using (bucket_id = 'guest-ids' and (public.is_owner() or owner_id = auth.uid()::text));

commit;
