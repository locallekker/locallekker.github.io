-- Migration: Ensure minimal profiles exist for owners referenced by businesses, merchants, memberships
-- Inserts minimal profile rows for any user IDs referenced by these tables when a profile is missing.
-- Idempotent: uses ON CONFLICT DO NOTHING

begin;

-- Create minimal profiles for owner_member_id in businesses
insert into public.profiles (id, email, name, created_at)
select b.owner_member_id,
       coalesce(au.email, 'no-email@unknown'),
       null,
       now()
from public.businesses b
left join public.profiles p on p.id = b.owner_member_id
left join auth.users au on au.id = b.owner_member_id
where p.id is null
on conflict (id) do nothing;

-- Create minimal profiles for user_id in trusted_partners
insert into public.profiles (id, email, name, created_at)
select tp.user_id,
       coalesce(au.email, 'no-email@unknown'),
       null,
       now()
from public.trusted_partners tp
left join public.profiles p on p.id = tp.user_id
left join auth.users au on au.id = tp.user_id
where p.id is null
on conflict (id) do nothing;

-- Create minimal profiles for user_id in memberships
insert into public.profiles (id, email, name, created_at)
select mem.user_id,
       coalesce(au.email, 'no-email@unknown'),
       null,
       now()
from public.memberships mem
left join public.profiles p on p.id = mem.user_id
left join auth.users au on au.id = mem.user_id
where p.id is null
on conflict (id) do nothing;

commit;