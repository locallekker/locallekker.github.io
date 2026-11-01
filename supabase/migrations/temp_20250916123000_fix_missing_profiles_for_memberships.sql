-- Migration: ensure profiles exist for any memberships.user_id
-- Inserts minimal profile rows for membership owners missing a profile
-- Idempotent: only inserts when a profile does not already exist

begin;

-- Insert minimal profiles for memberships that reference non-existent profiles.
-- Prefer pulling email from auth.users when available (Supabase default).
insert into public.profiles (id, name, email, role, created_at)
select
  m.user_id,
  null,                      -- name unknown; leave null
  u.email,                   -- try to use auth.users.email when present
  m.role,                    -- preserve role from memberships
  now()
from public.memberships m
left join auth.users u on u.id = m.user_id
where not exists (
  select 1 from public.profiles p where p.id = m.user_id
);

commit;
