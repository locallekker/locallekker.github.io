-- Migration: Update terminology from merchant/user to trusted partner/member
-- This migration updates role names and related terminology throughout the database

begin;

-- Update role values in memberships table
update public.memberships
set role = 'trusted_partner'
where role = 'merchant';

update public.memberships
set role = 'member'
where role = 'user';

-- Update role values in profiles table
update public.profiles
set role = 'trusted_partner'
where role = 'merchant';

update public.profiles
set role = 'member'
where role = 'user';

-- Update default role in profiles table constraint/trigger if needed
-- (The default is set in the table definition, so we need to update that too)
alter table public.profiles
alter column role set default 'member';

-- Update any policies that reference specific roles
-- Note: We'll need to recreate policies with new role names

-- Drop old policies that reference merchant/user roles (only if tables exist)
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'merchants') then
    drop policy if exists "Users can view own merchant record" on public.merchants;
  end if;
end $$;

drop policy if exists "Merchants can view own business" on public.businesses;
drop policy if exists "Merchants can update own business" on public.businesses;

-- Create new policies with updated terminology (skip if merchants table doesn't exist)
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'merchants') then
    create policy "Members can view own trusted partner record" on public.merchants
      for select using (auth.uid() = user_id);
  end if;
end $$;

create policy "Trusted partners can view own business" on public.businesses
  for select using (auth.uid() = owner_member_id);

create policy "Trusted partners can update own business" on public.businesses
  for update using (auth.uid() = owner_member_id);

-- Update any functions that reference role names
-- (This would need to be done for any stored functions that check roles)

-- Update indexes if they reference role names (they don't, they just index the column)

-- Rename merchants table to trusted_partners for clarity (optional but recommended)
-- Note: This is a major change that might break existing code, so we'll keep the table name for now
-- but update the conceptual naming in comments and policies

-- Add comments to clarify the new terminology
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'merchants') then
    comment on table public.merchants is 'Stores trusted partner information for businesses';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'trusted_partners') then
    comment on table public.trusted_partners is 'Stores trusted partner information for businesses';
  end if;
end $$;

comment on table public.memberships is 'Stores user role assignments (member, trusted_partner, admin)';
comment on column public.profiles.role is 'User role: member, trusted_partner, or admin';

commit;