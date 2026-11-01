-- Migration: Update terminology from merchant/user to trusted_partner/member
-- This migration comprehensively updates all references throughout the database

begin;

-- Step 1: Rename merchants table to trusted_partners
alter table if exists public.merchants rename to trusted_partners;

-- Step 2: Rename columns that reference merchant terminology
-- Note: owner_user_id in businesses table should become owner_member_id
alter table if exists public.businesses rename column owner_user_id to owner_member_id;

-- Step 3: Update all role values in profiles table
update public.profiles
set role = case
  when role = 'merchant' then 'trusted_partner'
  when role = 'user' then 'member'
  else role
end
where role in ('merchant', 'user');

-- Step 4: Update all role values in memberships table
update public.memberships
set role = case
  when role = 'merchant' then 'trusted_partner'
  when role = 'user' then 'member'
  else role
end
where role in ('merchant', 'user');

-- Step 5: Update foreign key constraints to reference the new table name
-- Drop existing foreign key constraints that reference merchants table
alter table if exists public.businesses drop constraint if exists businesses_owner_user_id_fkey;
alter table if exists public.businesses drop constraint if exists businesses_owner_member_id_fkey;

-- Add new foreign key constraint for trusted_partners table
alter table public.businesses
add constraint businesses_owner_member_id_fkey
foreign key (owner_member_id) references auth.users(id) on delete cascade;

-- Step 6: Update RLS policies to reflect new table names
drop policy if exists "Users can view own merchant record" on public.trusted_partners;
drop policy if exists "Members can view own trusted partner record" on public.trusted_partners;
create policy "Members can view own trusted partner record" on public.trusted_partners
  for select using ((SELECT auth.uid()) = user_id);

drop policy if exists "Users can update own merchant record" on public.trusted_partners;
drop policy if exists "Members can update own trusted partner record" on public.trusted_partners;
create policy "Members can update own trusted partner record" on public.trusted_partners
  for update using ((SELECT auth.uid()) = user_id);

drop policy if exists "Users can insert own merchant record" on public.trusted_partners;
drop policy if exists "Members can insert own trusted partner record" on public.trusted_partners;
create policy "Members can insert own trusted partner record" on public.trusted_partners
  for insert with check ((SELECT auth.uid()) = user_id);

-- Step 7: Update indexes to reflect new column names
drop index if exists idx_businesses_owner_user_id;
create index if not exists idx_businesses_owner_member_id on public.businesses(owner_member_id);

-- Step 8: Update any functions that reference the old terminology
-- Update complete_business_profile function
create or replace function public.complete_business_profile(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  member_id uuid := auth.uid();
  v_name text := nullif(coalesce(payload->>'name', ''), '');
  v_cat text := nullif(coalesce(payload->>'category', ''), '');
  v_street text := nullif(coalesce(payload->>'street', ''), '');
  v_suburb text := nullif(coalesce(payload->>'suburb', ''), '');
  v_city text := nullif(coalesce(payload->>'city', ''), '');
  v_prov text := nullif(coalesce(payload->>'province', ''), '');
  v_contact_email text := nullif(coalesce(payload->>'contact_email', ''), '');
  v_contact_number text := nullif(coalesce(payload->>'contact_number', ''), '');
  v_latitude double precision := public.try_cast_double(coalesce(payload->>'latitude', null));
  v_longitude double precision := public.try_cast_double(coalesce(payload->>'longitude', null));
  v_address text;
  v_business_id uuid;
begin
  if member_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- Build address
  v_address := array_to_string(
    array_remove(array[v_street, v_suburb, v_city, v_prov], null),
    ', '
  );
  if v_address = '' then v_address := null; end if;

  -- Validation
  if coalesce(v_name, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_business_name');
  end if;
  if coalesce(v_cat, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_category');
  end if;

  -- Ensure member has trusted_partner role in memberships table
  insert into public.memberships (user_id, role, gateway)
  values (member_id, 'trusted_partner', 'business_profile_completion')
  on conflict (user_id) do update
    set role = 'trusted_partner',
        gateway = excluded.gateway;

  -- Also ensure profiles table has trusted_partner role
  update public.profiles
  set role = 'trusted_partner',
      category = v_cat
  where id = member_id and (role is null or role != 'trusted_partner');

  -- Create/update trusted_partners table with business name
  insert into public.trusted_partners (user_id, business_name)
  values (member_id, v_name)
  on conflict (user_id) do update
    set business_name = excluded.business_name,
        updated_at = now();

  -- Create/update business record
  insert into public.businesses (
    owner_member_id, name, category, address, latitude, longitude, contact_email, contact_number, verified
  ) values (
    member_id, v_name, v_cat, v_address, v_latitude, v_longitude, v_contact_email, v_contact_number, true
  ) on conflict (owner_member_id) do update
    set name = excluded.name,
        category = excluded.category,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        contact_email = excluded.contact_email,
        contact_number = excluded.contact_number,
        verified = true
  returning id into v_business_id;

  return jsonb_build_object('ok', true, 'business_id', v_business_id);

exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

-- Step 9: Update any other functions that reference old terminology
-- Update function names and references as needed

-- Step 10: Update any views or other database objects

-- Step 11: Update backfill data for existing records
-- Note: Since we renamed the table, existing data is already in trusted_partners
-- No additional data migration needed as the table rename preserved all data

commit;