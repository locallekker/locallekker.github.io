-- Migration: fix missing profiles for existing memberships
-- Idempotent: inserts minimal profile records for any memberships.user_id that
-- do not have a corresponding row in public.profiles. Uses auth.users.email
-- when available to populate the email field.

begin;

-- Safe, idempotent insert: only creates profiles for user_ids not already present
insert into public.profiles (id, name, email, role, created_at)
select
  m.user_id,
  null::text,
  u.email,
  m.role,
  now()
from public.memberships m
left join public.profiles p on p.id = m.user_id
left join auth.users u on u.id = m.user_id
where p.id is null
  and m.user_id is not null;

commit;
