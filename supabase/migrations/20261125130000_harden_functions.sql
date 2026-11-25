-- Security hardening flagged by Supabase's security checker.
-- Reverse with supabase/rollbacks/20261125130000_harden_functions.down.sql
-- handle_new_user only runs as a trigger; nobody needs to call it directly.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
-- is_owner / is_member are used inside the security rules for signed-in users, so they keep
-- that right; signed-out visitors don't need them.
revoke execute on function public.is_owner() from public, anon;
revoke execute on function public.is_member() from public, anon;
grant execute on function public.is_owner() to authenticated;
grant execute on function public.is_member() to authenticated;
alter function public.touch_record() set search_path = public;
