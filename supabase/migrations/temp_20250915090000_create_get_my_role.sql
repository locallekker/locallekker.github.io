-- Create a SECURITY DEFINER helper that returns the current caller's role.
-- This function is intended to be called via RPC from the client when RLS
-- prevents direct SELECTs on membership/profile rows. The function runs as
-- the function owner (security definer) so it must be owned by a DB role that
-- has permission to read the underlying tables (typically the DB admin role
-- used for migrations).

drop function if exists public.get_my_role();

create function public.get_my_role()
returns text
security definer
SET search_path = public
language sql
as $$
  -- Prefer explicit membership row if present, otherwise fall back to profile
  -- This uses auth.uid() so it returns the role for the caller's JWT.
  select coalesce(
    (select m.role from memberships m where m.user_id = auth.uid() limit 1),
    (select p.role from profiles p where p.id = auth.uid() limit 1)
  );
$$;
