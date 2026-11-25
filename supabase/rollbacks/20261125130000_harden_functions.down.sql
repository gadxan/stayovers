-- Reverses 20261125130000_harden_functions.sql (restores Postgres' default function rights).
grant execute on function public.handle_new_user() to public;
grant execute on function public.is_owner() to public;
grant execute on function public.is_member() to public;
alter function public.touch_record() reset search_path;
