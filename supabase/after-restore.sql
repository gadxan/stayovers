-- Run after restoring a backup into a NEW Supabase project.
-- Database dumps leave out things that live in Supabase's own auth and storage schemas:
-- the trigger that creates a profile for each new login, the private ID-file bucket and its
-- access rules. This puts them back. Safe to run more than once.

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('guest-ids', 'guest-ids', false, 20971520,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'application/pdf'])
on conflict (id) do nothing;

drop policy if exists "guest ids: members upload" on storage.objects;
drop policy if exists "guest ids: members view" on storage.objects;
drop policy if exists "guest ids: owner or uploader deletes" on storage.objects;
drop policy if exists "guest ids: owner deletes" on storage.objects;
create policy "guest ids: members upload" on storage.objects
  for insert to authenticated with check (bucket_id = 'guest-ids' and public.is_member());
create policy "guest ids: members view" on storage.objects
  for select to authenticated using (bucket_id = 'guest-ids' and public.is_member());
create policy "guest ids: owner deletes" on storage.objects
  for delete to authenticated using (bucket_id = 'guest-ids' and public.is_owner());

-- live updates between phones
do $$ begin
  alter publication supabase_realtime add table public.bookings, public.transactions, public.recurring;
exception when others then null; end $$;
