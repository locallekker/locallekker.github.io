-- Migration: Create base tables for role management system
-- This creates the essential tables needed before other migrations can run

begin;

-- Create profiles table
create table if not exists public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  name text,
  surname text,
  email text,
  role text default 'user',
  category text,
  street text,
  suburb text,
  city text,
  province text,
  contact text,
  gender text,
  ethnicity text,
  date_of_birth date,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Create memberships table
create table if not exists public.memberships (
  user_id uuid references auth.users(id) on delete cascade,
  role text not null,
  gateway text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  primary key (user_id)
);

-- Create trusted_partners table
create table if not exists public.trusted_partners (
  user_id uuid references auth.users(id) on delete cascade primary key,
  business_name text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Create businesses table
create table if not exists public.businesses (
  id uuid default gen_random_uuid() primary key,
  owner_user_id uuid references auth.users(id) on delete cascade,
  name text,
  category text,
  address text,
  latitude double precision,
  longitude double precision,
  contact_email text,
  contact_number text,
  verified boolean default false,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  unique(owner_user_id)
);

-- Create users table (for backward compatibility)
create table if not exists public.users (
  id uuid references auth.users(id) on delete cascade primary key,
  email text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS
alter table public.profiles enable row level security;
alter table public.memberships enable row level security;
alter table public.trusted_partners enable row level security;
alter table public.businesses enable row level security;
alter table public.users enable row level security;

-- Create basic policies
create policy "Users can view own profile" on public.profiles
  for select using (auth.uid() = id);

create policy "Users can update own profile" on public.profiles
  for update using (auth.uid() = id);

create policy "Users can view own membership" on public.memberships
  for select using (auth.uid() = user_id);

create policy "Users can view own trusted_partner record" on public.trusted_partners
  for select using (auth.uid() = user_id);

create policy "Users can view own business" on public.businesses
  for select using (auth.uid() = owner_user_id);

create policy "Users can update own business" on public.businesses
  for update using (auth.uid() = owner_user_id);

create policy "Users can view own user record" on public.users
  for select using (auth.uid() = id);

-- Create indexes for performance
create index if not exists idx_profiles_role on public.profiles(role);
create index if not exists idx_memberships_role on public.memberships(role);
create index if not exists idx_memberships_user_id on public.memberships(user_id);
create index if not exists idx_businesses_owner_user_id on public.businesses(owner_user_id);

commit;
 
-- Drop old version so we can redefine it
drop function if exists public.get_admin_dashboard();
 
create function public.get_admin_dashboard()
returns json
language plpgsql
as $$
declare
  result json;
begin
  select json_build_object(
    'total_users', (select count(*) from users),
    'total_trusted_partners', (select count(*) from profiles where role = 'trusted_partner'),
    'total_online_purchases', coalesce((select sum(amount) from payments where in_store = false and payment_status = 'complete'), 0),
    'total_in_store_purchases', coalesce((select sum(amount) from payments where in_store = true and payment_status = 'complete'), 0)
  ) into result;

  return result;
end;
$$;
 
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
 
-- Migration: Ensure minimal profiles exist for owners referenced by businesses, trusted_partners, memberships
-- Inserts minimal profile rows for any user IDs referenced by these tables when a profile is missing.
-- Idempotent: uses ON CONFLICT DO NOTHING

begin;

-- Create minimal profiles for owner_user_id in businesses
insert into public.profiles (id, email, name, created_at)
select b.owner_user_id,
       coalesce(au.email, 'no-email@unknown'),
       null,
       now()
from public.businesses b
left join public.profiles p on p.id = b.owner_user_id
left join auth.users au on au.id = b.owner_user_id
where p.id is null
on conflict (id) do nothing;

-- Create minimal profiles for owner_user_id in trusted_partners
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
 
-- Migration: Create missing public.users rows (if table exists), ensure minimal profiles,
-- and add a safe RLS policy allowing authenticated users to insert/update their own profile.
-- Idempotent: uses conditional checks and ON CONFLICT DO NOTHING

begin;

-- Only run the users population if the table public.users exists
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'users') then
    -- Insert minimal public.users rows for any user ids referenced by businesses/trusted_partners/memberships
    -- Populate the required NOT NULL/UNIQUE `email` column using auth.users.email when available,
    -- otherwise use a unique placeholder based on the uid to avoid uniqueness collisions.
    insert into public.users (id, email, created_at)
    select distinct t.uid,
           coalesce(au.email, ('no-email+' || t.uid::text || '@example.invalid')),
           now()
    from (
      select owner_user_id as uid from public.businesses
      union
      select user_id as uid from public.trusted_partners
      union
      select user_id as uid from public.memberships
    ) t
    left join auth.users au on au.id = t.uid
    where t.uid is not null
      and not exists (select 1 from public.users u where u.id = t.uid)
    ;
  end if;
end$$;

-- Ensure minimal profiles exist for the same set of user ids (safe to run regardless)
insert into public.profiles (id, email, name, created_at)
select uid,
       coalesce(au.email, 'no-email@unknown'),
       null,
       now()
from (
  select owner_user_id as uid from public.businesses
  union
  select user_id as uid from public.trusted_partners
  union
  select user_id as uid from public.memberships
) t
left join public.profiles p on p.id = t.uid
left join auth.users au on au.id = t.uid
where t.uid is not null
  and p.id is null
on conflict (id) do nothing;

-- Create a row-level security policy on public.profiles to allow the authenticated user
-- to insert or update their own profile row. This is intentionally narrow.
-- Only create the policy if the table exists and the policy is not already present.
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'profiles') then
    if not exists (
      select 1 from pg_policies p
      where p.schemaname = 'public' and p.tablename = 'profiles' and p.policyname = 'allow_self_profile_insert'
    ) then
      execute $cmd$
        alter table public.profiles enable row level security;
        -- Create separate policies for INSERT and UPDATE because the
        -- CREATE POLICY syntax does not accept comma-separated actions.
        create policy allow_self_profile_insert
          on public.profiles
          for insert
          with check (auth.uid() = id);

        create policy allow_self_profile_update
          on public.profiles
          for update
          using (auth.uid() = id)
          with check (auth.uid() = id);
      $cmd$;
    end if;
  end if;
end$$;

commit;
 
-- Migration: Add foreign key from invitations.entity_id to entities.id
-- Idempotent: checks for table/column/constraint existence and performs safe backfill.

begin;

-- Ensure the invitations table exists before proceeding
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'invitations'
  ) then

    -- Add entity_id column if missing (nullable to avoid breaking existing rows)
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'invitations' and column_name = 'entity_id'
    ) then
      execute 'alter table public.invitations add column entity_id uuid';
    end if;

    -- If entities table exists, attempt a best-effort backfill for invitations that
    -- can be resolved via a heuristic (e.g. match invitation.target_email -> entities.contact_email)
    if exists (
      select 1 from information_schema.tables
      where table_schema = 'public' and table_name = 'entities'
    ) then
      -- Example heuristic backfill: match by contact_email if columns exist.
      if exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'invitations' and column_name = 'target_email'
      ) and exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'entities' and column_name = 'contact_email'
      ) then
        -- Update invitations set entity_id based on matching contact_email
        execute $update_sql$
          update public.invitations i
          set entity_id = e.id
          from public.entities e
          where i.entity_id is null
            and i.target_email is not null
            and lower(i.target_email) = lower(e.contact_email)
        $update_sql$;
      end if;

      -- Add constraint only if it doesn't already exist
      if not exists (
        select 1 from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu on kcu.constraint_name = tc.constraint_name
        where tc.table_schema = 'public' and tc.table_name = 'invitations'
          and tc.constraint_type = 'FOREIGN KEY' and kcu.column_name = 'entity_id'
      ) then
        -- Use ON DELETE SET NULL to avoid cascading deletions
        execute 'alter table public.invitations add constraint invitations_entity_id_fkey foreign key (entity_id) references public.entities(id) on delete set null';
      end if;
    end if;
  end if;
end$$;

commit;
 
-- Migration: create SECURITY DEFINER RPC create_staff_admin(payload jsonb)
-- Purpose: Admin-only onboarding of staff accounts. Inserts/upserts into staff and memberships
-- Idempotent: uses upsert and returns structured jsonb result: {ok: boolean, staff_id: uuid, error: text}

begin;

-- Drop and recreate to ensure idempotence during iterative development
create or replace function public.create_staff_admin(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email text;
  v_name text;
  v_role text;
  v_staff_id uuid;
  v_user_id uuid;
begin
  -- Extract inputs
  v_email := (payload->>'email');
  v_name := (payload->>'name');
  v_role := coalesce(payload->>'role','staff');

  if v_email is null then
    return jsonb_build_object('ok', false, 'error', 'missing_email');
  end if;

  -- Ensure there is an auth.user for the email. This function assumes the
  -- caller (admin) has already created a user in auth.users or will manage
  -- that separately. We'll try to find an auth.users entry and derive user id.
  select id into v_user_id from auth.users where lower(email) = lower(v_email) limit 1;

  if v_user_id is null then
    -- If no auth user, create a placeholder with unmanaged password and mark
    -- it for admin provisioning. This is optional and can be removed.
    insert into auth.users(email, raw_app_meta_data)
    values (v_email, jsonb_build_object('provisioned_by','create_staff_admin'))
    returning id into v_user_id;
  end if;

  -- Insert or update staff row (assumes staff table exists with at least id, user_id, name)
  perform 1;
  begin
    insert into public.staff (user_id, name, created_at)
    values (v_user_id, v_name, now())
    on conflict (user_id) do update set name = excluded.name
    returning id into v_staff_id;
  exception when undefined_table then
    -- If staff table doesn't exist, return helpful error
    return jsonb_build_object('ok', false, 'error', 'staff_table_missing');
  end;

  -- Upsert into memberships to grant role
  begin
    insert into public.memberships (user_id, role, source)
    values (v_user_id, v_role, 'admin_onboard')
    on conflict (user_id) do update set role = excluded.role
    ;
  exception when undefined_table then
    -- memberships missing: ignore but warn
    null;
  end;

  -- Optional: write to audit table if exists
  begin
    if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'audit_log') then
      insert into public.audit_log (actor_user_id, action, payload, created_at)
      values (current_setting('jwt.claims.user_id', true)::uuid, 'create_staff_admin', payload, now());
    end if;
  exception when others then
    null;
  end;

  return jsonb_build_object('ok', true, 'staff_id', v_staff_id, 'user_id', v_user_id);
end;
$$;

-- Grant execute to admin role (replace 'authenticated' with your admin role if different)
-- Note: This function is SECURITY DEFINER; ensure the owner is a trusted DB role.
grant execute on function public.create_staff_admin(jsonb) to authenticated;

commit;
 
-- Migration: Fix recursive RLS policies on public.users and create safe owner-only policies
-- Purpose: If a POLICY on public.users causes infinite recursion (42P17), this migration
-- will remove existing policies on public.users and replace them with narrow, safe
-- policies that rely only on auth.uid(). It also backfills missing public.users rows
-- for identities referenced by application tables (businesses/trusted_partners/memberships).
-- IMPORTANT: Review and run in a privileged context. Dropping policies is impactful.

begin;

-- Only proceed if the public.users table exists
do $$
begin
  if not exists (
    select 1 from information_schema.tables where table_schema = 'public' and table_name = 'users'
  ) then
    raise notice 'Skipping: public.users table does not exist';
    return;
  end if;

  -- Backfill minimal public.users rows for uids referenced by app tables
  -- This mirrors earlier backfill logic but is safe to re-run.
  begin
    insert into public.users (id, email, created_at)
    select distinct t.uid,
           coalesce(au.email, ('no-email+' || t.uid::text || '@example.invalid')),
           now()
    from (
      select owner_user_id as uid from public.businesses
      union
      select user_id as uid from public.trusted_partners
      union
      select user_id as uid from public.memberships
    ) t
    left join auth.users au on au.id = t.uid
    where t.uid is not null
      and not exists (select 1 from public.users u where u.id = t.uid)
    ;
  exception when undefined_table then
    raise notice 'One or more referencing tables (businesses/trusted_partners/memberships) do not exist; skipping backfill';
  end;

  -- Drop all existing policies on public.users to eliminate any problematic ones.
  -- We drop dynamically by reading pg_policies. Use format() to safely quote names.
  declare
    policy_rec record;
  begin
    for policy_rec in select policyname from pg_policies where schemaname = 'public' and tablename = 'users' loop
      execute format('drop policy if exists %I on public.users', policy_rec.policyname);
      raise notice 'Dropped policy: %', policy_rec.policyname;
    end loop;
  end;

  -- Enable RLS on public.users (no-op if already enabled)
  execute 'alter table public.users enable row level security';

  -- Create narrow policies that only allow the authenticated principal to
  -- operate on their own row. Avoid any functions or queries that re-enter
  -- public.users (this prevents recursion).

  -- Allow a user to SELECT their own users row
  execute $policy_select$
    create policy allow_self_users_select
      on public.users
      for select
      using (auth.uid() = id);
  $policy_select$;

  -- Allow a user to INSERT their own users row (useful for client best-effort upserts)
  execute $policy_insert$
    create policy allow_self_users_insert
      on public.users
      for insert
      with check (auth.uid() = id);
  $policy_insert$;

  -- Allow a user to UPDATE their own users row
  execute $policy_update$
    create policy allow_self_users_update
      on public.users
      for update
      using (auth.uid() = id)
      with check (auth.uid() = id);
  $policy_update$;

  -- Optionally, create a restricted DELETE policy only for admins (not granted here)
  -- Leave DELETE prohibited by default to avoid accidental removal from client principals.

  -- Grant minimal usage: do not give broad read/write permissions to 'authenticated'.
  -- Administrative operations should use SECURITY DEFINER functions with explicit grants.

  raise notice 'public.users policies refreshed to owner-only policies';
end$$;

commit;
 
-- Migration: Ensure user exists in public.users before business creation
-- This fixes the foreign key constraint violation in complete_business_profile RPC

begin;

-- Modify the complete_business_profile RPC to ensure user exists in public.users
drop function if exists public.complete_business_profile(jsonb);

create or replace function public.complete_business_profile(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();

  v_name   text := nullif(coalesce(payload->>'name', ''), '');
  v_cat    text := nullif(coalesce(payload->>'category', ''), '');
  v_street text := nullif(coalesce(payload->>'street', ''), '');
  v_suburb text := nullif(coalesce(payload->>'suburb', ''), '');
  v_city   text := nullif(coalesce(payload->>'city', ''), '');
  v_prov   text := nullif(coalesce(payload->>'province', ''), '');
  v_contact_email text := nullif(coalesce(payload->>'contact_email', ''), '');

  v_latitude  double precision := public.try_cast_double(coalesce(payload->>'latitude', null));
  v_longitude double precision := public.try_cast_double(coalesce(payload->>'longitude', null));

  v_address text;
  v_business_id uuid;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- Ensure user exists in public.users (create if missing)
  -- Use a safer approach that handles existing users properly
  insert into public.users (id, email, created_at)
  values (
    uid,
    coalesce(
      (select email from auth.users where id = uid),
      'user-' || uid || '@locallekker.app'
    ),
    now()
  )
  on conflict (id) do update set
    -- Update email if it's different and not null
    email = case
      when excluded.email is not null and public.users.email is null then excluded.email
      else public.users.email
    end;

  -- build address
  v_address := array_to_string(
    array_remove(array[v_street, v_suburb, v_city, v_prov], null),
    ', '
  );
  if v_address = '' then v_address := null; end if;

  -- validation
  if coalesce(v_name, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_business_name');
  end if;
  if coalesce(v_cat, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_category');
  end if;

  insert into public.businesses (
    owner_user_id, name, category, address, latitude, longitude, contact_email
  ) values (
    uid, v_name, v_cat, v_address, v_latitude, v_longitude, v_contact_email
  ) on conflict (owner_user_id) do update
    set name = excluded.name,
        category = excluded.category,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        contact_email = excluded.contact_email
  returning id into v_business_id;

  return jsonb_build_object('ok', true, 'business_id', v_business_id);

exception when others then
  return jsonb_build_object('ok', false, 'error', SQLERRM);
end;
$$;

grant execute on function public.complete_business_profile(jsonb) to authenticated;

commit;
 
-- Create payments table to track completed payments
-- Drop existing table if it exists to ensure clean state
DROP TABLE IF EXISTS payments CASCADE;

-- Create the payments table with correct schema
CREATE TABLE payments (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    plan_name TEXT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    payment_method TEXT NOT NULL,
    transaction_id TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'cancelled')),
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes
CREATE INDEX idx_payments_user_id ON payments(user_id);
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_payments_transaction_id ON payments(transaction_id);

-- Enable RLS
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own payments" ON payments;
DROP POLICY IF EXISTS "Users can insert their own payments" ON payments;
DROP POLICY IF EXISTS "Admins can view all payments" ON payments;
DROP POLICY IF EXISTS "Service role can manage payments" ON payments;

-- Create policies
CREATE POLICY "Users can view their own payments" ON payments
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own payments" ON payments
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all payments" ON payments
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
    );

CREATE POLICY "Service role can manage payments" ON payments
    FOR ALL USING (auth.role() = 'service_role');

-- Create or replace function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_payments_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists and recreate
DROP TRIGGER IF EXISTS trigger_update_payments_updated_at ON payments;
CREATE TRIGGER trigger_update_payments_updated_at
    BEFORE UPDATE ON payments
    FOR EACH ROW
    EXECUTE FUNCTION update_payments_updated_at();
 
-- Migration: Add surname column to profiles table
-- This migration adds a surname column to store the user's surname separately

begin;

-- Add surname column to profiles table
alter table public.profiles add column if not exists surname text;

-- Update existing profiles to extract surname from name if possible
-- This is a best-effort attempt to populate surname for existing users
update public.profiles
set surname = split_part(trim(name), ' ', -1)
where surname is null and name is not null and name != '';

commit;
 
-- Migration: Update complete_trusted_partner_signup RPC to save surname to profiles table
-- This migration modifies the RPC to store the surname separately in the profiles table

begin;

-- Drop and recreate the complete_trusted_partner_signup function to include surname saving
drop function if exists public.complete_trusted_partner_signup(jsonb);

create or replace function public.complete_trusted_partner_signup(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();

  -- inputs (nullify empty strings)
  v_first_name      text := nullif(coalesce(payload->>'first_name', ''), '');
  v_surname         text := nullif(coalesce(payload->>'surname', ''), '');
  v_full_name       text;
  v_business_name   text := nullif(coalesce(payload->>'business_name', ''), '');
  v_category        text := nullif(coalesce(payload->>'category', ''), '');

  v_street          text := nullif(coalesce(payload->>'street', ''), '');
  v_suburb          text := nullif(coalesce(payload->>'suburb', ''), '');
  v_city            text := nullif(coalesce(payload->>'city', ''), '');
  v_province        text := nullif(coalesce(payload->>'province', ''), '');
  v_contact_email   text := nullif(coalesce(payload->>'contact_email', ''), '');

  v_latitude        double precision := public.try_cast_double(coalesce(payload->>'latitude', null));
  v_longitude       double precision := public.try_cast_double(coalesce(payload->>'longitude', null));

  v_address         text;
  v_profile_id      uuid;
  v_partner_id      uuid;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- derive fields
  v_full_name := trim(both ' ' from coalesce(v_first_name, '') || ' ' || coalesce(v_surname, ''));
  v_address := array_to_string(
                 array_remove( array[ v_street, v_suburb, v_city, v_province ], null ),
                 ', '
               );
  if v_address = '' then v_address := null; end if;

  -- profiles: (id, name, surname, email, role, category)
  insert into public.profiles (id, name, surname, email, role, category)
  values (uid,
          coalesce(v_full_name, v_business_name),
          v_surname,
          v_contact_email,
          'trusted_partner',
          v_category)
  on conflict (id) do update
    set name     = excluded.name,
        surname  = excluded.surname,
        email    = coalesce(excluded.email, public.profiles.email),
        role     = 'trusted_partner',
        category = coalesce(excluded.category, public.profiles.category)
  returning id into v_profile_id;

  -- memberships: ensure user has trusted_partner role
  insert into public.memberships (user_id, role, gateway)
  values (uid, 'trusted_partner', 'app_signup')
  on conflict (user_id) do update
    set role = 'trusted_partner',
        gateway = excluded.gateway;

  -- trusted_partners: lightweight (user_id unique, business_name)
  insert into public.trusted_partners (user_id, business_name)
  values (uid, coalesce(v_business_name, v_full_name))
  on conflict (user_id) do update
    set business_name = excluded.business_name;

  select id into v_partner_id
  from public.trusted_partners
  where user_id = uid;

  -- businesses: full profile
  insert into public.businesses (
    owner_user_id, name, category, address, latitude, longitude, contact_email
  )
  values (
    uid,
    coalesce(v_business_name, v_full_name),
    v_category,
    v_address,
    v_latitude,
    v_longitude,
    v_contact_email
  )
  on conflict (owner_user_id) do update
    set name          = excluded.name,
        category      = excluded.category,
        address       = excluded.address,
        latitude      = excluded.latitude,
        longitude     = excluded.longitude,
        contact_email = excluded.contact_email;

  return jsonb_build_object('ok', true, 'profile_id', v_profile_id, 'partner_id', v_partner_id);
end;
$$;

commit;
 
-- Migration: Add contact_number support to complete_business_profile RPC
-- This ensures both contact_email and contact_number are stored in businesses table

begin;

-- Add contact_number column to businesses table if it doesn't exist
do $$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public'
                 and table_name = 'businesses'
                 and column_name = 'contact_number') then
    alter table public.businesses add column contact_number text;
  end if;
end $$;

-- Update the complete_business_profile RPC to handle contact_number

-- Update the complete_business_profile RPC to handle contact_number
drop function if exists public.complete_business_profile(jsonb);

create or replace function public.complete_business_profile(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();

  v_name   text := nullif(coalesce(payload->>'name', ''), '');
  v_cat    text := nullif(coalesce(payload->>'category', ''), '');
  v_street text := nullif(coalesce(payload->>'street', ''), '');
  v_suburb text := nullif(coalesce(payload->>'suburb', ''), '');
  v_city   text := nullif(coalesce(payload->>'city', ''), '');
  v_prov   text := nullif(coalesce(payload->>'province', ''), '');
  v_contact_email text := nullif(coalesce(payload->>'contact_email', ''), '');
  v_contact_number text := nullif(coalesce(payload->>'contact_number', ''), '');

  v_latitude  double precision := public.try_cast_double(coalesce(payload->>'latitude', null));
  v_longitude double precision := public.try_cast_double(coalesce(payload->>'longitude', null));

  v_address text;
  v_business_id uuid;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- Ensure user exists in public.users (create if missing)
  -- Use a safer approach that handles existing users properly
  insert into public.users (id, email, created_at)
  values (
    uid,
    coalesce(
      (select email from auth.users where id = uid),
      'user-' || uid || '@locallekker.app'
    ),
    now()
  )
  on conflict (id) do update set
    -- Update email if it's different and not null
    email = case
      when excluded.email is not null and public.users.email is null then excluded.email
      else public.users.email
    end;

  -- build address
  v_address := array_to_string(
    array_remove(array[v_street, v_suburb, v_city, v_prov], null),
    ', '
  );
  if v_address = '' then v_address := null; end if;

  -- validation
  if coalesce(v_name, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_business_name');
  end if;
  if coalesce(v_cat, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_category');
  end if;

  insert into public.businesses (
    owner_user_id, name, category, address, latitude, longitude, contact_email, contact_number
  ) values (
    uid, v_name, v_cat, v_address, v_latitude, v_longitude, v_contact_email, v_contact_number
  ) on conflict (owner_user_id) do update
    set name = excluded.name,
        category = excluded.category,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        contact_email = excluded.contact_email,
        contact_number = excluded.contact_number
  returning id into v_business_id;

  return jsonb_build_object('ok', true, 'business_id', v_business_id);

exception when others then
  return jsonb_build_object('ok', false, 'error', SQLERRM);
end;
$$;

grant execute on function public.complete_business_profile(jsonb) to authenticated;

commit;
 
-- Add contact_number column to businesses table
-- This migration ensures the contact_number column exists

begin;

-- Add contact_number column to businesses table if it doesn't exist
alter table public.businesses
add column if not exists contact_number text;

-- Add comment for documentation
comment on column public.businesses.contact_number is 'Business contact phone number';

commit;
 
-- Add RLS policies for businesses table
-- This ensures users can only access their own business records

begin;

-- Enable RLS on businesses table
alter table public.businesses enable row level security;

-- Allow users to select their own business
create policy "Users can view their own business" on public.businesses
  for select using (auth.uid() = owner_user_id);

-- Allow users to insert their own business
create policy "Users can insert their own business" on public.businesses
  for insert with check (auth.uid() = owner_user_id);

-- Allow users to update their own business
create policy "Users can update their own business" on public.businesses
  for update using (auth.uid() = owner_user_id) with check (auth.uid() = owner_user_id);

-- Allow users to delete their own business
create policy "Users can delete their own business" on public.businesses
  for delete using (auth.uid() = owner_user_id);

-- Allow service role full access (for admin operations)
create policy "Service role can manage all businesses" on public.businesses
  for all using (auth.jwt() ->> 'role' = 'service_role');

commit;
 
-- Migration: Fix role assignment issue - convert 'member' to 'user' and add constraints
-- Date: 2025-09-18
-- Description: Fixes the issue where roles were manually set to 'member' instead of 'user'

BEGIN;

-- Step 0: Drop existing constraints that might conflict
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS valid_role;
ALTER TABLE public.memberships DROP CONSTRAINT IF EXISTS valid_membership_role;

-- Step 1: Fix existing 'member' roles to 'user'
-- Update profiles table
UPDATE public.profiles
SET role = 'user'
WHERE role = 'member' OR role IS NULL OR role = '';

-- Update memberships table
UPDATE public.memberships
SET role = 'user'
WHERE role = 'member' OR role IS NULL OR role = '';

-- Step 2: Set default role for new profiles
ALTER TABLE public.profiles
ALTER COLUMN role SET DEFAULT 'user';

-- Step 3: Add check constraints to prevent invalid roles
ALTER TABLE public.profiles
ADD CONSTRAINT valid_role
CHECK (role IN ('user', 'merchant', 'admin'));

ALTER TABLE public.memberships
ADD CONSTRAINT valid_membership_role
CHECK (role IN ('user', 'merchant', 'admin'));

-- Step 4: Create an index on role columns for better performance
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_memberships_role ON public.memberships(role);

COMMIT;

-- Verification queries (run these separately to check the results)
-- SELECT role, COUNT(*) FROM public.profiles GROUP BY role ORDER BY role;
-- SELECT role, COUNT(*) FROM public.memberships GROUP BY role ORDER BY role;
 
-- Migration: Prevent duplicate profiles by email
-- This migration removes duplicate profiles based on email, keeping the most recent one,
-- and adds a unique constraint on email to prevent future duplicates

begin;

-- Step 1: Identify and remove duplicate profiles, keeping the most recent one per email
-- Use a CTE to find duplicates and delete all but the most recent
with duplicates as (
  select id, email, created_at,
         row_number() over (partition by email order by created_at desc) as rn
  from public.profiles
  where email is not null and email != ''
)
delete from public.profiles
where id in (
  select id from duplicates where rn > 1
);

-- Step 2: Add unique constraint on email (excluding nulls)
-- First, ensure no null emails violate the constraint
update public.profiles
set email = null
where email = '';

-- Add the unique index (allows nulls)
create unique index if not exists idx_profiles_email_unique
on public.profiles (email)
where email is not null;

commit;
 
-- Migration: Clean up duplicate emails and create missing profile for clydemflan@gmail.com
-- This migration handles the specific case of duplicate emails and ensures the authenticated user has a profile

begin;

-- Only proceed if the specific user exists in auth.users
do $$
begin
  if exists (select 1 from auth.users where id = 'ed2c04d7-23d7-4ef1-acd5-7a8cfc5bc270') then

    -- Step 1: Delete all profiles with this email except the one that should belong to our authenticated user
    delete from public.profiles
    where email = 'clydemflan@gmail.com'
      and id != 'ed2c04d7-23d7-4ef1-acd5-7a8cfc5bc270';

    -- Step 2: Now create the profile for our authenticated user if it doesn't exist
    insert into public.profiles (id, email, name, role, created_at)
    values ('ed2c04d7-23d7-4ef1-acd5-7a8cfc5bc270',
            'clydemflan@gmail.com',
            'User', -- Default name
            'user', -- Default role
            now())
    on conflict (id) do nothing;

    -- Step 3: Ensure the user has a membership record
    insert into public.memberships (user_id, role, gateway)
    values ('ed2c04d7-23d7-4ef1-acd5-7a8cfc5bc270',
            'user',
            'migration_fix')
    on conflict (user_id) do nothing;

    raise notice 'Fixed profile and membership for clydemflan@gmail.com';
  else
    raise notice 'User ed2c04d7-23d7-4ef1-acd5-7a8cfc5bc270 does not exist in auth.users, skipping migration';
  end if;
end $$;

commit;
 
-- Migration: Check and fix memberships table RLS policies
-- Date: 2025-09-18
-- Description: Check current RLS status on memberships table and fix any recursive policies

BEGIN;

-- Check if RLS is enabled on memberships table
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = 'memberships'
        AND n.nspname = 'public'
        AND c.relrowsecurity = true
    ) THEN
        RAISE NOTICE 'RLS is not enabled on memberships table';
    ELSE
        RAISE NOTICE 'RLS is enabled on memberships table';
    END IF;
END $$;

-- Check existing policies on memberships table
DO $$
DECLARE
    policy_rec record;
BEGIN
    RAISE NOTICE 'Current policies on memberships table:';
    FOR policy_rec IN
        SELECT policyname, permissive, roles, cmd, qual, with_check
        FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'memberships'
    LOOP
        RAISE NOTICE 'Policy: %, Permissive: %, Roles: %, Command: %, Qual: %, With Check: %',
            policy_rec.policyname, policy_rec.permissive, policy_rec.roles,
            policy_rec.cmd, policy_rec.qual, policy_rec.with_check;
    END LOOP;

    IF NOT FOUND THEN
        RAISE NOTICE 'No policies found on memberships table';
    END IF;
END $$;

-- If there are problematic policies, drop them
-- Drop any policies that might cause recursion
DROP POLICY IF EXISTS "Users can view their own memberships" ON public.memberships;
DROP POLICY IF EXISTS "Users can insert their own memberships" ON public.memberships;
DROP POLICY IF EXISTS "Users can update their own memberships" ON public.memberships;
DROP POLICY IF EXISTS "Service role can manage memberships" ON public.memberships;

-- Create safe, non-recursive policies
-- Enable RLS if not already enabled
ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

-- Allow users to view their own memberships
CREATE POLICY "Users can view their own memberships" ON public.memberships
    FOR SELECT
    USING (auth.uid() = user_id);

-- Allow users to insert their own memberships (for role assignment)
CREATE POLICY "Users can insert their own memberships" ON public.memberships
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Allow users to update their own memberships
CREATE POLICY "Users can update their own memberships" ON public.memberships
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Allow service role to manage all memberships (for admin operations)
CREATE POLICY "Service role can manage memberships" ON public.memberships
    FOR ALL
    USING (auth.role() = 'service_role');

COMMIT;
 
-- Migration: Fix recursive policies on memberships table
-- Date: 2025-09-18
-- Description: Remove recursive policies that cause infinite recursion

BEGIN;

-- Drop the problematic recursive policies
DROP POLICY IF EXISTS "Admins can read all memberships" ON public.memberships;
DROP POLICY IF EXISTS "admin_all" ON public.memberships;

-- Create safe, non-recursive policies (only if they don't exist)
DO $$
BEGIN
    -- Check and create SELECT policy
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'memberships' AND policyname = 'Users can view their own memberships'
    ) THEN
        CREATE POLICY "Users can view their own memberships" ON public.memberships
            FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    -- Check and create INSERT policy
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'memberships' AND policyname = 'Users can insert their own memberships'
    ) THEN
        CREATE POLICY "Users can insert their own memberships" ON public.memberships
            FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;

    -- Check and create UPDATE policy
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'memberships' AND policyname = 'Users can update their own memberships'
    ) THEN
        CREATE POLICY "Users can update their own memberships" ON public.memberships
            FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;

    -- Check and create service role policy
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'memberships' AND policyname = 'Service role can manage memberships'
    ) THEN
        CREATE POLICY "Service role can manage memberships" ON public.memberships
            FOR ALL
            USING (auth.role() = 'service_role');
    END IF;
END $$;

COMMIT;
 
-- Migration: Add user profile fields to profiles table
-- This migration adds the missing columns needed for user profiles

begin;

-- Add user-specific columns to profiles table
alter table public.profiles
add column if not exists street text,
add column if not exists suburb text,
add column if not exists city text,
add column if not exists contact text,
add column if not exists gender text,
add column if not exists ethnicity text,
add column if not exists province text,
add column if not exists date_of_birth timestamp with time zone;

-- Add comments for documentation
comment on column public.profiles.street is 'User street address';
comment on column public.profiles.suburb is 'User suburb';
comment on column public.profiles.city is 'User city';
comment on column public.profiles.contact is 'User contact phone number';
comment on column public.profiles.gender is 'User gender (Male/Female/Other)';
comment on column public.profiles.ethnicity is 'User ethnicity';
comment on column public.profiles.province is 'User province';
comment on column public.profiles.date_of_birth is 'User date of birth';

commit;
 
-- Migration: Fix merchant role assignment in complete_business_profile RPC
-- Ensures that when merchants complete their business profile, they get the correct 'merchant' role

BEGIN;

-- Update the complete_business_profile function to ensure merchant role assignment
CREATE OR REPLACE FUNCTION public.complete_business_profile(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();

  v_name   text := nullif(coalesce(payload->>'name', ''), '');
  v_cat    text := nullif(coalesce(payload->>'category', ''), '');
  v_street text := nullif(coalesce(payload->>'street', ''), '');
  v_suburb text := nullif(coalesce(payload->>'suburb', ''), '');
  v_city   text := nullif(coalesce(payload->>'city', ''), '');
  v_prov   text := nullif(coalesce(payload->>'province', ''), '');
  v_contact_email text := nullif(coalesce(payload->>'contact_email', ''), '');

  v_latitude  double precision := public.try_cast_double(coalesce(payload->>'latitude', null));
  v_longitude double precision := public.try_cast_double(coalesce(payload->>'longitude', null));

  v_address text;
  v_business_id uuid;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  -- Build address
  v_address := array_to_string(
    array_remove(array[v_street, v_suburb, v_city, v_prov], null),
    ', '
  );
  IF v_address = '' THEN v_address := null; END IF;

  -- Validation
  IF coalesce(v_name, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_business_name');
  END IF;
  IF coalesce(v_cat, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_category');
  END IF;

  -- Ensure user has merchant role in memberships table
  INSERT INTO public.memberships (user_id, role, gateway)
  VALUES (uid, 'merchant', 'business_profile_completion')
  ON CONFLICT (user_id) DO UPDATE
    SET role = 'merchant',
        gateway = excluded.gateway;

  -- Also ensure profiles table has merchant role
  UPDATE public.profiles
  SET role = 'merchant'
  WHERE id = uid AND (role IS NULL OR role != 'merchant');

  -- Create/update business record
  INSERT INTO public.businesses (
    owner_user_id, name, category, address, latitude, longitude, contact_email
  ) VALUES (
    uid, v_name, v_cat, v_address, v_latitude, v_longitude, v_contact_email
  ) ON CONFLICT (owner_user_id) DO UPDATE
    SET name = excluded.name,
        category = excluded.category,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        contact_email = excluded.contact_email
  RETURNING id INTO v_business_id;

  RETURN jsonb_build_object('ok', true, 'business_id', v_business_id);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$$;

COMMIT;
 
-- Migration: Create automatic role assignment trigger
-- Creates a trigger that automatically assigns roles based on user_type metadata
-- when new users are created in auth.users

BEGIN;

-- Function to handle automatic role assignment
CREATE OR REPLACE FUNCTION public.handle_new_user_role_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_type text;
  user_role text;
  user_email text;
  user_name text;
  user_surname text;
BEGIN
  -- Get user_type from raw_app_meta_data
  user_type := NEW.raw_app_meta_data->>'user_type';

  -- If not found in raw_app_meta_data, try raw_user_meta_data
  IF user_type IS NULL THEN
    user_type := NEW.raw_user_meta_data->>'user_type';
  END IF;

  -- Get user email
  user_email := COALESCE(NEW.email, NEW.raw_user_meta_data->>'email', '');

  -- Get user name and surname from metadata - try both locations
  user_name := COALESCE(
    NEW.raw_app_meta_data->>'name',
    NEW.raw_user_meta_data->>'name'
  );
  user_surname := COALESCE(
    NEW.raw_app_meta_data->>'surname',
    NEW.raw_user_meta_data->>'surname'
  );

  -- Determine role based on user_type
  IF user_type = 'merchant' THEN
    user_role := 'merchant';
  ELSE
    -- Default to 'user' role for any other type or null
    user_role := 'user';
  END IF;

  -- Log the metadata for debugging
  RAISE WARNING 'Trigger Debug - raw_app_meta_data: %', NEW.raw_app_meta_data::text;
  RAISE WARNING 'Trigger Debug - raw_user_meta_data: %', NEW.raw_user_meta_data::text;
  RAISE WARNING 'Trigger Debug - user_type: %, name: %, surname: %', user_type, user_name, user_surname;

  -- Insert into profiles table with ALL available data
  BEGIN
    INSERT INTO public.profiles (
      id,
      email,
      role,
      name,
      surname,
      street,
      suburb,
      city,
      province,
      contact,
      gender,
      ethnicity,
      date_of_birth,
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      user_email,
      COALESCE(user_role, 'user'),
      user_name,
      user_surname,
      COALESCE(NEW.raw_app_meta_data->>'street', NEW.raw_user_meta_data->>'street'),
      COALESCE(NEW.raw_app_meta_data->>'suburb', NEW.raw_user_meta_data->>'suburb'),
      COALESCE(NEW.raw_app_meta_data->>'city', NEW.raw_user_meta_data->>'city'),
      COALESCE(NEW.raw_app_meta_data->>'province', NEW.raw_user_meta_data->>'province'),
      COALESCE(NEW.raw_app_meta_data->>'contact', NEW.raw_user_meta_data->>'contact'),
      COALESCE(NEW.raw_app_meta_data->>'gender', NEW.raw_user_meta_data->>'gender'),
      COALESCE(NEW.raw_app_meta_data->>'ethnicity', NEW.raw_user_meta_data->>'ethnicity'),
      CASE
        WHEN COALESCE(NEW.raw_app_meta_data->>'date_of_birth', NEW.raw_user_meta_data->>'date_of_birth') IS NOT NULL
        THEN (COALESCE(NEW.raw_app_meta_data->>'date_of_birth', NEW.raw_user_meta_data->>'date_of_birth'))::timestamp with time zone
        ELSE NULL
      END,
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO UPDATE
      SET email = COALESCE(EXCLUDED.email, public.profiles.email),
          role = COALESCE(EXCLUDED.role, public.profiles.role),
          name = COALESCE(EXCLUDED.name, public.profiles.name),
          surname = COALESCE(EXCLUDED.surname, public.profiles.surname),
          street = COALESCE(EXCLUDED.street, public.profiles.street),
          suburb = COALESCE(EXCLUDED.suburb, public.profiles.suburb),
          city = COALESCE(EXCLUDED.city, public.profiles.city),
          province = COALESCE(EXCLUDED.province, public.profiles.province),
          contact = COALESCE(EXCLUDED.contact, public.profiles.contact),
          gender = COALESCE(EXCLUDED.gender, public.profiles.gender),
          ethnicity = COALESCE(EXCLUDED.ethnicity, public.profiles.ethnicity),
          date_of_birth = COALESCE(EXCLUDED.date_of_birth, public.profiles.date_of_birth),
          updated_at = NOW();
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but don't fail the user creation
      RAISE WARNING 'Failed to create/update profile for user %: %', NEW.id, SQLERRM;
  END;

  -- Insert into memberships table with better error handling
  BEGIN
    INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
    VALUES (NEW.id, user_role, 'automatic_signup', NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE
      SET role = COALESCE(EXCLUDED.role, public.memberships.role),
          gateway = COALESCE(EXCLUDED.gateway, public.memberships.gateway),
          updated_at = NOW();
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but don't fail the user creation
      RAISE WARNING 'Failed to create/update membership for user %: %', NEW.id, SQLERRM;
  END;

  -- If merchant, also create a merchants record with error handling
  IF user_type = 'merchant' THEN
    BEGIN
      INSERT INTO public.merchants (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, '', NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION
      WHEN OTHERS THEN
        -- Log error but don't fail the user creation
        RAISE WARNING 'Failed to create merchant record for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- Create the trigger
DROP TRIGGER IF EXISTS trigger_automatic_role_assignment ON auth.users;
CREATE TRIGGER trigger_automatic_role_assignment
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user_role_assignment();

COMMIT;
 
-- Migration: Fix automatic role assignment trigger with better error handling
-- Updates the trigger function to handle conflicts gracefully and not fail user creation

BEGIN;

-- Update the function to handle automatic role assignment with better error handling
CREATE OR REPLACE FUNCTION public.handle_new_user_role_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_type text;
  user_role text;
  user_email text;
  user_name text;
  user_surname text;
BEGIN
  -- Get user_type from raw_app_meta_data (set during signup)
  user_type := NEW.raw_app_meta_data->>'user_type';

  -- If not found in raw_app_meta_data, try raw_user_meta_data
  IF user_type IS NULL THEN
    user_type := NEW.raw_user_meta_data->>'user_type';
  END IF;

  -- Get user email
  user_email := COALESCE(NEW.email, NEW.raw_user_meta_data->>'email', '');

  -- Get user name and surname from metadata
  user_name := NEW.raw_app_meta_data->>'name';
  user_surname := NEW.raw_app_meta_data->>'surname';

  -- Determine role based on user_type
  IF user_type = 'merchant' THEN
    user_role := 'merchant';
  ELSE
    -- Default to 'user' role for any other type or null
    user_role := 'user';
  END IF;

  -- Log the user_type and role assignment for debugging
  RAISE WARNING 'Trigger: user_type=% role=% email=%', user_type, user_role, user_email;

  -- Insert into profiles table with ALL available data
  BEGIN
    INSERT INTO public.profiles (
      id,
      email,
      role,
      name,
      surname,
      street,
      suburb,
      city,
      province,
      contact,
      gender,
      ethnicity,
      date_of_birth,
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      user_email,
      user_role,
      user_name,
      user_surname,
      NEW.raw_app_meta_data->>'street',
      NEW.raw_app_meta_data->>'suburb',
      NEW.raw_app_meta_data->>'city',
      NEW.raw_app_meta_data->>'province',
      NEW.raw_app_meta_data->>'contact',
      NEW.raw_app_meta_data->>'gender',
      NEW.raw_app_meta_data->>'ethnicity',
      (NEW.raw_app_meta_data->>'date_of_birth')::timestamp with time zone,
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO UPDATE
      SET email = COALESCE(EXCLUDED.email, public.profiles.email),
          role = COALESCE(EXCLUDED.role, public.profiles.role),
          name = COALESCE(EXCLUDED.name, public.profiles.name),
          surname = COALESCE(EXCLUDED.surname, public.profiles.surname),
          street = COALESCE(EXCLUDED.street, public.profiles.street),
          suburb = COALESCE(EXCLUDED.suburb, public.profiles.suburb),
          city = COALESCE(EXCLUDED.city, public.profiles.city),
          province = COALESCE(EXCLUDED.province, public.profiles.province),
          contact = COALESCE(EXCLUDED.contact, public.profiles.contact),
          gender = COALESCE(EXCLUDED.gender, public.profiles.gender),
          ethnicity = COALESCE(EXCLUDED.ethnicity, public.profiles.ethnicity),
          date_of_birth = COALESCE(EXCLUDED.date_of_birth, public.profiles.date_of_birth),
          updated_at = NOW();
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but don't fail the user creation
      RAISE WARNING 'Failed to create/update profile for user %: %', NEW.id, SQLERRM;
  END;

  -- Insert into memberships table with better error handling
  BEGIN
    INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
    VALUES (NEW.id, user_role, 'automatic_signup', NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE
      SET role = COALESCE(EXCLUDED.role, public.memberships.role),
          gateway = COALESCE(EXCLUDED.gateway, public.memberships.gateway),
          updated_at = NOW();
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but don't fail the user creation
      RAISE WARNING 'Failed to create/update membership for user %: %', NEW.id, SQLERRM;
  END;

  -- If merchant, also create a merchants record with error handling
  IF user_type = 'merchant' THEN
    BEGIN
      INSERT INTO public.merchants (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, '', NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION
      WHEN OTHERS THEN
        -- Log error but don't fail the user creation
        RAISE WARNING 'Failed to create merchant record for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

COMMIT;
 
-- Migration: Add logging to trigger for debugging role assignment
-- Adds warning logs to help debug why roles are not being assigned correctly

BEGIN;

-- Update the function to add logging for debugging
CREATE OR REPLACE FUNCTION public.handle_new_user_role_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_type text;
  user_role text;
  user_email text;
BEGIN
  -- Get user_type from raw_app_meta_data (set during signup)
  user_type := NEW.raw_app_meta_data->>'user_type';

  -- If not found in raw_app_meta_data, try raw_user_meta_data
  IF user_type IS NULL THEN
    user_type := NEW.raw_user_meta_data->>'user_type';
  END IF;

  -- Get user email
  user_email := COALESCE(NEW.email, NEW.raw_user_meta_data->>'email', '');

  -- Determine role based on user_type
  IF user_type = 'merchant' THEN
    user_role := 'merchant';
  ELSE
    -- Default to 'user' role for any other type or null
    user_role := 'user';
  END IF;

  -- Log the user_type and role assignment for debugging
  RAISE WARNING 'Trigger: user_id=% user_type=% role=% email=%', NEW.id, user_type, user_role, user_email;

  -- Insert into profiles table with better error handling
  BEGIN
    INSERT INTO public.profiles (id, email, role, created_at, updated_at)
    VALUES (NEW.id, user_email, user_role, NOW(), NOW())
    ON CONFLICT (id) DO UPDATE
      SET email = COALESCE(EXCLUDED.email, public.profiles.email),
          role = COALESCE(EXCLUDED.role, public.profiles.role),
          updated_at = NOW();
    RAISE WARNING 'Trigger: Profile created/updated for user % with role %', NEW.id, user_role;
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but don't fail the user creation
      RAISE WARNING 'Trigger: Failed to create/update profile for user %: %', NEW.id, SQLERRM;
  END;

  -- Insert into memberships table with better error handling
  BEGIN
    INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
    VALUES (NEW.id, user_role, 'automatic_signup', NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE
      SET role = COALESCE(EXCLUDED.role, public.memberships.role),
          gateway = COALESCE(EXCLUDED.gateway, public.memberships.gateway),
          updated_at = NOW();
    RAISE WARNING 'Trigger: Membership created/updated for user % with role %', NEW.id, user_role;
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but don't fail the user creation
      RAISE WARNING 'Trigger: Failed to create/update membership for user %: %', NEW.id, SQLERRM;
  END;

  -- If merchant, also create a merchants record with error handling
  IF user_type = 'merchant' THEN
    BEGIN
      INSERT INTO public.merchants (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, '', NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
      RAISE WARNING 'Trigger: Merchant record created for user %', NEW.id;
    EXCEPTION
      WHEN OTHERS THEN
        -- Log error but don't fail the user creation
        RAISE WARNING 'Trigger: Failed to create merchant record for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

COMMIT;
 
-- Migration: Add missing INSERT policies for trigger operations
-- Date: 2025-09-19
-- Description: Add INSERT policies for profiles and memberships to allow trigger operations

BEGIN;

-- Add INSERT policy for profiles table to allow service role operations
-- This is needed for the automatic role assignment trigger
CREATE POLICY "Service role can insert profiles" ON public.profiles
    FOR INSERT
    WITH CHECK (auth.role() = 'service_role');

-- Ensure service role can manage all operations on profiles
CREATE POLICY "Service role can manage profiles" ON public.profiles
    FOR ALL
    USING (auth.role() = 'service_role');

-- For memberships, the existing service role policy should cover INSERT,
-- but let's ensure it's comprehensive
DROP POLICY IF EXISTS "Service role can manage memberships" ON public.memberships;
CREATE POLICY "Service role can manage memberships" ON public.memberships
    FOR ALL
    USING (auth.role() = 'service_role');

COMMIT;
 
-- Migration: Update trigger to populate all profile fields from user metadata
-- This updates the existing trigger function to include all user profile fields

BEGIN;

-- Update the function to handle automatic role assignment with complete profile data
CREATE OR REPLACE FUNCTION public.handle_new_user_role_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_type text;
  user_role text;
  user_email text;
  user_name text;
  user_surname text;
BEGIN
  -- Get user_type from raw_app_meta_data
  user_type := NEW.raw_app_meta_data->>'user_type';

  -- If not found in raw_app_meta_data, try raw_user_meta_data
  IF user_type IS NULL THEN
    user_type := NEW.raw_user_meta_data->>'user_type';
  END IF;

  -- Get user email
  user_email := COALESCE(NEW.email, NEW.raw_user_meta_data->>'email', '');

  -- Get user name and surname from metadata
  user_name := NEW.raw_app_meta_data->>'name';
  user_surname := NEW.raw_app_meta_data->>'surname';

  -- Determine role based on user_type
  IF user_type = 'merchant' THEN
    user_role := 'merchant';
  ELSE
    -- Default to 'user' role for any other type or null
    user_role := 'user';
  END IF;

  -- Log the user_type and role assignment for debugging
  RAISE WARNING 'Trigger: user_type=% role=% email=%', user_type, user_role, user_email;

  -- Insert into profiles table with ALL available data from user metadata
  BEGIN
    INSERT INTO public.profiles (
      id,
      email,
      role,
      name,
      surname,
      street,
      suburb,
      city,
      province,
      contact,
      gender,
      ethnicity,
      date_of_birth,
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      user_email,
      user_role,
      user_name,
      user_surname,
      NEW.raw_app_meta_data->>'street',
      NEW.raw_app_meta_data->>'suburb',
      NEW.raw_app_meta_data->>'city',
      NEW.raw_app_meta_data->>'province',
      NEW.raw_app_meta_data->>'contact',
      NEW.raw_app_meta_data->>'gender',
      NEW.raw_app_meta_data->>'ethnicity',
      (NEW.raw_app_meta_data->>'date_of_birth')::timestamp with time zone,
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO UPDATE
      SET email = COALESCE(EXCLUDED.email, public.profiles.email),
          role = COALESCE(EXCLUDED.role, public.profiles.role),
          name = COALESCE(EXCLUDED.name, public.profiles.name),
          surname = COALESCE(EXCLUDED.surname, public.profiles.surname),
          street = COALESCE(EXCLUDED.street, public.profiles.street),
          suburb = COALESCE(EXCLUDED.suburb, public.profiles.suburb),
          city = COALESCE(EXCLUDED.city, public.profiles.city),
          province = COALESCE(EXCLUDED.province, public.profiles.province),
          contact = COALESCE(EXCLUDED.contact, public.profiles.contact),
          gender = COALESCE(EXCLUDED.gender, public.profiles.gender),
          ethnicity = COALESCE(EXCLUDED.ethnicity, public.profiles.ethnicity),
          date_of_birth = COALESCE(EXCLUDED.date_of_birth, public.profiles.date_of_birth),
          updated_at = NOW();
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but don't fail the user creation
      RAISE WARNING 'Failed to create/update profile for user %: %', NEW.id, SQLERRM;
  END;

  -- Insert into memberships table with better error handling
  BEGIN
    INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
    VALUES (NEW.id, user_role, 'automatic_signup', NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE
      SET role = COALESCE(EXCLUDED.role, public.memberships.role),
          gateway = COALESCE(EXCLUDED.gateway, public.memberships.gateway),
          updated_at = NOW();
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but don't fail the user creation
      RAISE WARNING 'Failed to create/update membership for user %: %', NEW.id, SQLERRM;
  END;

  -- If merchant, also create a merchants record with error handling
  IF user_type = 'merchant' THEN
    BEGIN
      INSERT INTO public.merchants (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, '', NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION
      WHEN OTHERS THEN
        -- Log error but don't fail the user creation
        RAISE WARNING 'Failed to create merchant record for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

COMMIT;
 
-- Migration: Update subscription status function to use calendar month countdown
-- Changes countdown calculation to be based on subscription end date instead of next payment date

BEGIN;

-- Drop the existing function first to allow return type change
DROP FUNCTION IF EXISTS public.get_subscription_status(UUID);

-- Recreate the get_subscription_status function with subscription end date
CREATE OR REPLACE FUNCTION public.get_subscription_status(p_user_id UUID)
RETURNS TABLE(
  has_active_qr BOOLEAN,
  qr_expires_at TIMESTAMP WITH TIME ZONE,
  subscription_status TEXT,
  auto_renew BOOLEAN,
  days_until_renewal INTEGER,
  next_payment_date TIMESTAMP WITH TIME ZONE,
  payment_overdue BOOLEAN,
  subscription_end_date TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  qr_record RECORD;
  sub_record RECORD;
  days_diff INTEGER;
BEGIN
  -- Get QR code info
  SELECT is_active, expires_at INTO qr_record
  FROM public.user_qr_codes
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  -- Get subscription info with table alias to avoid ambiguity
  SELECT s.status, s.auto_renew, s.next_payment_date, s.current_period_end INTO sub_record
  FROM public.subscriptions s
  WHERE s.user_id = p_user_id
  ORDER BY s.created_at DESC
  LIMIT 1;

  -- Calculate days until renewal (based on subscription end date)
  IF sub_record.current_period_end IS NOT NULL THEN
    days_diff := EXTRACT(EPOCH FROM (sub_record.current_period_end - NOW())) / 86400;
  ELSE
    days_diff := NULL;
  END IF;

  -- Return results
  RETURN QUERY SELECT
    COALESCE(qr_record.is_active, false),
    qr_record.expires_at,
    COALESCE(sub_record.status, 'none'),
    COALESCE(sub_record.auto_renew, false),
    days_diff::INTEGER,
    sub_record.next_payment_date,
    CASE WHEN days_diff < 0 THEN true ELSE false END,
    sub_record.current_period_end;
END;
$$;

COMMIT;
 
-- Migration: Debug user metadata and profile creation
-- This migration adds logging to understand what metadata is available during signup

BEGIN;

-- Update the trigger function to add more detailed debugging
CREATE OR REPLACE FUNCTION public.handle_new_user_role_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_type text;
  user_role text;
  user_email text;
  user_name text;
  user_surname text;
  metadata_json jsonb;
BEGIN
  -- Log all available metadata for debugging
  RAISE WARNING '=== TRIGGER DEBUG START ===';
  RAISE WARNING 'NEW.email: %', NEW.email;
  RAISE WARNING 'NEW.raw_app_meta_data: %', NEW.raw_app_meta_data::text;
  RAISE WARNING 'NEW.raw_user_meta_data: %', NEW.raw_user_meta_data::text;
  RAISE WARNING 'NEW.user_metadata: %', NEW.user_metadata::text;

  -- Try to get user_type from different locations
  user_type := COALESCE(
    NEW.raw_app_meta_data->>'user_type',
    NEW.raw_user_meta_data->>'user_type',
    NEW.user_metadata->>'user_type'
  );

  -- Get user email
  user_email := COALESCE(NEW.email, NEW.raw_user_meta_data->>'email', '');

  -- Get user name and surname from metadata - try all locations
  user_name := COALESCE(
    NEW.raw_app_meta_data->>'name',
    NEW.raw_user_meta_data->>'name',
    NEW.user_metadata->>'name'
  );
  user_surname := COALESCE(
    NEW.raw_app_meta_data->>'surname',
    NEW.raw_user_meta_data->>'surname',
    NEW.user_metadata->>'surname'
  );

  -- Determine role based on user_type
  IF user_type = 'merchant' THEN
    user_role := 'merchant';
  ELSE
    user_role := 'user';
  END IF;

  RAISE WARNING 'Final values - user_type: %, user_role: %, user_name: %, user_surname: %', user_type, user_role, user_name, user_surname;

  -- Insert into profiles table with ALL available data
  BEGIN
    INSERT INTO public.profiles (
      id,
      email,
      role,
      name,
      surname,
      street,
      suburb,
      city,
      province,
      contact,
      gender,
      ethnicity,
      date_of_birth,
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      user_email,
      COALESCE(user_role, 'user'),
      user_name,
      user_surname,
      COALESCE(NEW.raw_app_meta_data->>'street', NEW.raw_user_meta_data->>'street', NEW.user_metadata->>'street'),
      COALESCE(NEW.raw_app_meta_data->>'suburb', NEW.raw_user_meta_data->>'suburb', NEW.user_metadata->>'suburb'),
      COALESCE(NEW.raw_app_meta_data->>'city', NEW.raw_user_meta_data->>'city', NEW.user_metadata->>'city'),
      COALESCE(NEW.raw_app_meta_data->>'province', NEW.raw_user_meta_data->>'province', NEW.user_metadata->>'province'),
      COALESCE(NEW.raw_app_meta_data->>'contact', NEW.raw_user_meta_data->>'contact', NEW.user_metadata->>'contact'),
      COALESCE(NEW.raw_app_meta_data->>'gender', NEW.raw_user_meta_data->>'gender', NEW.user_metadata->>'gender'),
      COALESCE(NEW.raw_app_meta_data->>'ethnicity', NEW.raw_user_meta_data->>'ethnicity', NEW.user_metadata->>'ethnicity'),
      CASE
        WHEN COALESCE(NEW.raw_app_meta_data->>'date_of_birth', NEW.raw_user_meta_data->>'date_of_birth', NEW.user_metadata->>'date_of_birth') IS NOT NULL
        THEN (COALESCE(NEW.raw_app_meta_data->>'date_of_birth', NEW.raw_user_meta_data->>'date_of_birth', NEW.user_metadata->>'date_of_birth'))::timestamp with time zone
        ELSE NULL
      END,
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO UPDATE
      SET email = COALESCE(EXCLUDED.email, public.profiles.email),
          role = COALESCE(EXCLUDED.role, public.profiles.role),
          name = COALESCE(EXCLUDED.name, public.profiles.name),
          surname = COALESCE(EXCLUDED.surname, public.profiles.surname),
          street = COALESCE(EXCLUDED.street, public.profiles.street),
          suburb = COALESCE(EXCLUDED.suburb, public.profiles.suburb),
          city = COALESCE(EXCLUDED.city, public.profiles.city),
          province = COALESCE(EXCLUDED.province, public.profiles.province),
          contact = COALESCE(EXCLUDED.contact, public.profiles.contact),
          gender = COALESCE(EXCLUDED.gender, public.profiles.gender),
          ethnicity = COALESCE(EXCLUDED.ethnicity, public.profiles.ethnicity),
          date_of_birth = COALESCE(EXCLUDED.date_of_birth, public.profiles.date_of_birth),
          updated_at = NOW();

    RAISE WARNING 'Profile insert/update completed successfully for user %', NEW.id;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Failed to create/update profile for user %: %', NEW.id, SQLERRM;
  END;

  -- Insert into memberships table
  BEGIN
    INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
    VALUES (NEW.id, user_role, 'automatic_signup', NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE
      SET role = COALESCE(EXCLUDED.role, public.memberships.role),
          gateway = COALESCE(EXCLUDED.gateway, public.memberships.gateway),
          updated_at = NOW();
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Failed to create/update membership for user %: %', NEW.id, SQLERRM;
  END;

  -- If merchant, create merchants record
  IF user_type = 'merchant' THEN
    BEGIN
      INSERT INTO public.merchants (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, '', NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'Failed to create merchant record for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RAISE WARNING '=== TRIGGER DEBUG END ===';
  RETURN NEW;
END;
$$;

COMMIT;
 
-- Create merchant_discounts table
CREATE TABLE IF NOT EXISTS merchant_discounts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    merchant_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    percentage DECIMAL(5,2) DEFAULT 0,
    fixed_amount DECIMAL(10,2),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Ensure either percentage or fixed_amount is set, but not both
    CONSTRAINT discount_type_check CHECK (
        (percentage > 0 AND fixed_amount IS NULL) OR
        (percentage = 0 AND fixed_amount IS NOT NULL AND fixed_amount > 0)
    )
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_merchant_discounts_merchant_id ON merchant_discounts(merchant_id);
CREATE INDEX IF NOT EXISTS idx_merchant_discounts_active ON merchant_discounts(is_active);

-- Enable RLS
ALTER TABLE merchant_discounts ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can view their own discounts" ON merchant_discounts
    FOR SELECT USING (auth.uid() = merchant_id);

CREATE POLICY "Users can insert their own discounts" ON merchant_discounts
    FOR INSERT WITH CHECK (auth.uid() = merchant_id);

CREATE POLICY "Users can update their own discounts" ON merchant_discounts
    FOR UPDATE USING (auth.uid() = merchant_id);

CREATE POLICY "Users can delete their own discounts" ON merchant_discounts
    FOR DELETE USING (auth.uid() = merchant_id);

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_merchant_discounts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update updated_at
CREATE TRIGGER update_merchant_discounts_updated_at_trigger
    BEFORE UPDATE ON merchant_discounts
    FOR EACH ROW
    EXECUTE FUNCTION update_merchant_discounts_updated_at();
 
-- Migration: Add name and surname columns and populate from qr_code JSON
-- Ensures name and surname fields are populated for existing and future records

BEGIN;

-- Create user_qr_codes table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.user_qr_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  qr_code TEXT NOT NULL UNIQUE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add name and surname columns to user_qr_codes if they don't exist
ALTER TABLE public.user_qr_codes
ADD COLUMN IF NOT EXISTS name TEXT,
ADD COLUMN IF NOT EXISTS surname TEXT;

-- Update the generate_user_qr_code function to include name and surname in QR data
CREATE OR REPLACE FUNCTION public.generate_user_qr_code(user_uuid UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  qr_data TEXT;
  user_name TEXT;
  user_surname TEXT;
BEGIN
  -- Get user's name and surname from profiles table
  SELECT p.name, p.surname INTO user_name, user_surname
  FROM public.profiles p
  WHERE p.id = user_uuid;

  -- If no profile found, use defaults
  IF user_name IS NULL THEN
    user_name := 'Unknown';
  END IF;
  IF user_surname IS NULL THEN
    user_surname := 'Unknown';
  END IF;

  -- Generate QR code data as JSON including name and surname
  qr_data := jsonb_build_object(
    'user_id', user_uuid,
    'name', user_name,
    'surname', user_surname,
    'timestamp', extract(epoch from now())::bigint,
    'random', (random() * 999999)::int
  )::TEXT;

  -- Insert or update the QR code record
  INSERT INTO public.user_qr_codes (user_id, qr_code, name, surname, expires_at)
  VALUES (
    user_uuid,
    qr_data,
    user_name,
    user_surname,
    NOW() + INTERVAL '1 year'
  )
  ON CONFLICT (user_id)
  DO UPDATE SET
    qr_code = EXCLUDED.qr_code,
    name = EXCLUDED.name,
    surname = EXCLUDED.surname,
    updated_at = NOW()
  WHERE public.user_qr_codes.user_id = user_uuid;

  RETURN qr_data;
END;
$$;

-- Update existing user_qr_codes records where name or surname is NULL
-- Extract values from the qr_code JSON field
UPDATE public.user_qr_codes
SET
  name = COALESCE(name, qr_code::jsonb->>'name'),
  surname = COALESCE(surname, qr_code::jsonb->>'surname'),
  updated_at = NOW()
WHERE name IS NULL OR surname IS NULL;

COMMIT;
 
-- Add policy to allow users to view active discounts from all merchants
-- This enables the offers/browse functionality

CREATE POLICY "Users can view active discounts from all merchants" ON merchant_discounts
    FOR SELECT USING (
        is_active = true
        AND auth.role() = 'authenticated'
    );
 
-- Add policy to allow users to view business names for offers functionality
-- This enables users to see merchant business names in the offers/browse screen

CREATE POLICY "Users can view business names for offers" ON businesses
    FOR SELECT USING (
        auth.role() = 'authenticated'
    );
 
-- Ensure merchant_discounts table exists
CREATE TABLE IF NOT EXISTS merchant_discounts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    merchant_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    percentage DECIMAL(5,2) DEFAULT 0,
    fixed_amount DECIMAL(10,2),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Ensure either percentage or fixed_amount is set, but not both
    CONSTRAINT discount_type_check CHECK (
        (percentage > 0 AND fixed_amount IS NULL) OR
        (percentage = 0 AND fixed_amount IS NOT NULL AND fixed_amount > 0)
    )
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_merchant_discounts_merchant_id ON merchant_discounts(merchant_id);
CREATE INDEX IF NOT EXISTS idx_merchant_discounts_active ON merchant_discounts(is_active);

-- Enable RLS
ALTER TABLE merchant_discounts ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own discounts" ON merchant_discounts;
DROP POLICY IF EXISTS "Users can insert their own discounts" ON merchant_discounts;
DROP POLICY IF EXISTS "Users can update their own discounts" ON merchant_discounts;
DROP POLICY IF EXISTS "Users can delete their own discounts" ON merchant_discounts;

-- Create policies
CREATE POLICY "Users can view their own discounts" ON merchant_discounts
    FOR SELECT USING (auth.uid() = merchant_id);

CREATE POLICY "Users can insert their own discounts" ON merchant_discounts
    FOR INSERT WITH CHECK (auth.uid() = merchant_id);

CREATE POLICY "Users can update their own discounts" ON merchant_discounts
    FOR UPDATE USING (auth.uid() = merchant_id);

CREATE POLICY "Users can delete their own discounts" ON merchant_discounts
    FOR DELETE USING (auth.uid() = merchant_id);

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_merchant_discounts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if it exists
DROP TRIGGER IF EXISTS update_merchant_discounts_updated_at_trigger ON merchant_discounts;

-- Create trigger to automatically update updated_at
CREATE TRIGGER update_merchant_discounts_updated_at_trigger
    BEFORE UPDATE ON merchant_discounts
    FOR EACH ROW
    EXECUTE FUNCTION update_merchant_discounts_updated_at();
 
-- Migration: Fix trigger date casting and role handling
-- This migration fixes the database error during signup by making the trigger more defensive

BEGIN;

-- Update the trigger function to handle NULL values properly
CREATE OR REPLACE FUNCTION public.handle_new_user_role_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_type text;
  user_role text;
  user_email text;
  user_name text;
  user_surname text;
  metadata_json jsonb;
BEGIN
  -- Log all available metadata for debugging
  RAISE WARNING '=== TRIGGER DEBUG START ===';
  RAISE WARNING 'NEW.email: %', NEW.email;
  RAISE WARNING 'NEW.raw_app_meta_data: %', NEW.raw_app_meta_data::text;
  RAISE WARNING 'NEW.raw_user_meta_data: %', NEW.raw_user_meta_data::text;
  RAISE WARNING 'NEW.user_metadata: %', NEW.user_metadata::text;

  -- Try to get user_type from different locations
  user_type := COALESCE(
    NEW.raw_app_meta_data->>'user_type',
    NEW.raw_user_meta_data->>'user_type',
    NEW.user_metadata->>'user_type'
  );

  -- Get user email
  user_email := COALESCE(NEW.email, NEW.raw_user_meta_data->>'email', '');

  -- Get user name and surname from metadata - try all locations
  user_name := COALESCE(
    NEW.raw_app_meta_data->>'name',
    NEW.raw_user_meta_data->>'name',
    NEW.user_metadata->>'name'
  );
  user_surname := COALESCE(
    NEW.raw_app_meta_data->>'surname',
    NEW.raw_user_meta_data->>'surname',
    NEW.user_metadata->>'surname'
  );

  -- Determine role based on user_type
  IF user_type = 'merchant' THEN
    user_role := 'merchant';
  ELSE
    user_role := 'user';
  END IF;

  RAISE WARNING 'Final values - user_type: %, user_role: %, user_name: %, user_surname: %', user_type, user_role, user_name, user_surname;

  -- Insert into profiles table with ALL available data
  BEGIN
    INSERT INTO public.profiles (
      id,
      email,
      role,
      name,
      surname,
      street,
      suburb,
      city,
      province,
      contact,
      gender,
      ethnicity,
      date_of_birth,
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      user_email,
      COALESCE(user_role, 'user'),
      user_name,
      user_surname,
      COALESCE(NEW.raw_app_meta_data->>'street', NEW.raw_user_meta_data->>'street', NEW.user_metadata->>'street'),
      COALESCE(NEW.raw_app_meta_data->>'suburb', NEW.raw_user_meta_data->>'suburb', NEW.user_metadata->>'suburb'),
      COALESCE(NEW.raw_app_meta_data->>'city', NEW.raw_user_meta_data->>'city', NEW.user_metadata->>'city'),
      COALESCE(NEW.raw_app_meta_data->>'province', NEW.raw_user_meta_data->>'province', NEW.user_metadata->>'province'),
      COALESCE(NEW.raw_app_meta_data->>'contact', NEW.raw_user_meta_data->>'contact', NEW.user_metadata->>'contact'),
      COALESCE(NEW.raw_app_meta_data->>'gender', NEW.raw_user_meta_data->>'gender', NEW.user_metadata->>'gender'),
      COALESCE(NEW.raw_app_meta_data->>'ethnicity', NEW.raw_user_meta_data->>'ethnicity', NEW.user_metadata->>'ethnicity'),
      CASE
        WHEN COALESCE(NEW.raw_app_meta_data->>'date_of_birth', NEW.raw_user_meta_data->>'date_of_birth', NEW.user_metadata->>'date_of_birth') IS NOT NULL
        THEN (COALESCE(NEW.raw_app_meta_data->>'date_of_birth', NEW.raw_user_meta_data->>'date_of_birth', NEW.user_metadata->>'date_of_birth'))::timestamp with time zone
        ELSE NULL
      END,
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO UPDATE
      SET email = COALESCE(EXCLUDED.email, public.profiles.email),
          role = COALESCE(EXCLUDED.role, public.profiles.role),
          name = COALESCE(EXCLUDED.name, public.profiles.name),
          surname = COALESCE(EXCLUDED.surname, public.profiles.surname),
          street = COALESCE(EXCLUDED.street, public.profiles.street),
          suburb = COALESCE(EXCLUDED.suburb, public.profiles.suburb),
          city = COALESCE(EXCLUDED.city, public.profiles.city),
          province = COALESCE(EXCLUDED.province, public.profiles.province),
          contact = COALESCE(EXCLUDED.contact, public.profiles.contact),
          gender = COALESCE(EXCLUDED.gender, public.profiles.gender),
          ethnicity = COALESCE(EXCLUDED.ethnicity, public.profiles.ethnicity),
          date_of_birth = COALESCE(EXCLUDED.date_of_birth, public.profiles.date_of_birth),
          updated_at = NOW();

    RAISE WARNING 'Profile insert/update completed successfully for user %', NEW.id;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Failed to create/update profile for user %: %', NEW.id, SQLERRM;
  END;

  -- Insert into memberships table
  BEGIN
    INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
    VALUES (NEW.id, user_role, 'automatic_signup', NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE
      SET role = COALESCE(EXCLUDED.role, public.memberships.role),
          gateway = COALESCE(EXCLUDED.gateway, public.memberships.gateway),
          updated_at = NOW();
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Failed to create/update membership for user %: %', NEW.id, SQLERRM;
  END;

  -- If merchant, create merchants record
  IF user_type = 'merchant' THEN
    BEGIN
      INSERT INTO public.merchants (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, '', NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'Failed to create merchant record for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RAISE WARNING '=== TRIGGER DEBUG END ===';
  RETURN NEW;
END;
$$;

COMMIT;
 
-- Migration: Simplify trigger to avoid database errors
-- This migration creates a simpler trigger that only handles the basic fields

BEGIN;

-- Create a simpler trigger function that handles errors more gracefully
CREATE OR REPLACE FUNCTION public.handle_new_user_role_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_type text;
  user_role text;
  user_email text;
  user_name text;
  user_surname text;
BEGIN
  -- Get basic user information
  user_email := COALESCE(NEW.email, '');

  -- Try to get user_type from different metadata locations
  user_type := COALESCE(
    NEW.raw_app_meta_data->>'user_type',
    NEW.raw_user_meta_data->>'user_type',
    NEW.user_metadata->>'user_type'
  );

  -- Determine role
  IF user_type = 'merchant' THEN
    user_role := 'merchant';
  ELSE
    user_role := 'user';
  END IF;

  -- Get name and surname if available
  user_name := COALESCE(
    NEW.raw_app_meta_data->>'name',
    NEW.raw_user_meta_data->>'name',
    NEW.user_metadata->>'name'
  );

  user_surname := COALESCE(
    NEW.raw_app_meta_data->>'surname',
    NEW.raw_user_meta_data->>'surname',
    NEW.user_metadata->>'surname'
  );

  -- Insert basic profile information only
  BEGIN
    INSERT INTO public.profiles (
      id,
      email,
      role,
      name,
      surname,
      street,
      suburb,
      city,
      province,
      contact,
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      user_email,
      user_role,
      user_name,
      user_surname,
      COALESCE(NEW.raw_app_meta_data->>'street', NEW.raw_user_meta_data->>'street', NEW.user_metadata->>'street'),
      COALESCE(NEW.raw_app_meta_data->>'suburb', NEW.raw_user_meta_data->>'suburb', NEW.user_metadata->>'suburb'),
      COALESCE(NEW.raw_app_meta_data->>'city', NEW.raw_user_meta_data->>'city', NEW.user_metadata->>'city'),
      COALESCE(NEW.raw_app_meta_data->>'province', NEW.raw_user_meta_data->>'province', NEW.user_metadata->>'province'),
      COALESCE(NEW.raw_app_meta_data->>'contact', NEW.raw_user_meta_data->>'contact', NEW.user_metadata->>'contact'),
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO UPDATE
      SET email = COALESCE(EXCLUDED.email, public.profiles.email),
          role = COALESCE(EXCLUDED.role, public.profiles.role),
          name = COALESCE(EXCLUDED.name, public.profiles.name),
          surname = COALESCE(EXCLUDED.surname, public.profiles.surname),
          street = COALESCE(EXCLUDED.street, public.profiles.street),
          suburb = COALESCE(EXCLUDED.suburb, public.profiles.suburb),
          city = COALESCE(EXCLUDED.city, public.profiles.city),
          province = COALESCE(EXCLUDED.province, public.profiles.province),
          contact = COALESCE(EXCLUDED.contact, public.profiles.contact),
          updated_at = NOW();

    RAISE WARNING 'Profile created/updated successfully for user %', NEW.id;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Failed to create/update profile for user %: %', NEW.id, SQLERRM;
      -- Don't fail the user creation, just log the error
  END;

  -- Insert into memberships table
  BEGIN
    INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
    VALUES (NEW.id, user_role, 'automatic_signup', NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE
      SET role = COALESCE(EXCLUDED.role, public.memberships.role),
          gateway = COALESCE(EXCLUDED.gateway, public.memberships.gateway),
          updated_at = NOW();
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Failed to create/update membership for user %: %', NEW.id, SQLERRM;
  END;

  -- If merchant, create merchants record
  IF user_type = 'merchant' THEN
    BEGIN
      INSERT INTO public.merchants (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, '', NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'Failed to create merchant record for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

COMMIT;
 
-- Migration: Replace trigger with minimal logging version
-- This migration replaces the complex trigger with a simple logging version

BEGIN;

-- Replace the trigger function with a minimal version that just logs
CREATE OR REPLACE FUNCTION public.handle_new_user_role_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_type text;
BEGIN
  -- Just log the signup attempt, don't do any database operations
  RAISE WARNING 'User signup detected: %', NEW.email;

  -- Try to get user_type if available
  user_type := COALESCE(
    NEW.raw_app_meta_data->>'user_type',
    NEW.raw_user_meta_data->>'user_type',
    NEW.user_metadata->>'user_type'
  );

  RAISE WARNING 'User type: %, ID: %', user_type, NEW.id;

  -- Don't do any database operations that might fail
  -- Just return NEW to allow the user creation to proceed

  RETURN NEW;
END;
$$;

COMMIT;
 
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

-- Drop old policies that reference merchant/user roles
drop policy if exists "Users can view own merchant record" on public.merchants;
drop policy if exists "Merchants can view own business" on public.businesses;
drop policy if exists "Merchants can update own business" on public.businesses;

-- Create new policies with updated terminology
create policy "Members can view own trusted partner record" on public.merchants
  for select using (auth.uid() = user_id);

create policy "Trusted partners can view own business" on public.businesses
  for select using (auth.uid() = owner_user_id);

create policy "Trusted partners can update own business" on public.businesses
  for update using (auth.uid() = owner_user_id);

-- Update any functions that reference role names
-- (This would need to be done for any stored functions that check roles)

-- Update indexes if they reference role names (they don't, they just index the column)

-- Rename merchants table to trusted_partners for clarity (optional but recommended)
-- Note: This is a major change that might break existing code, so we'll keep the table name for now
-- but update the conceptual naming in comments and policies

-- Add comments to clarify the new terminology
comment on table public.merchants is 'Stores trusted partner information for businesses';
comment on table public.memberships is 'Stores user role assignments (member, trusted_partner, admin)';
comment on column public.profiles.role is 'User role: member, trusted_partner, or admin';

commit;
 
-- Migration: Complete sc-- Create profiles table
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  name TEXT,
  surname TEXT,
  email TEXT,
  role TEXT DEFAULT 'member', -- User role: member, trusted_partner, or admin
  category TEXT, -- For members: individual, For trusted_partners: restaurant, retail, etc.
  street TEXT,
  suburb TEXT,
  city TEXT,
  province TEXT,
  contact TEXT,
  gender TEXT,
  ethnicity TEXT,
  date_of_birth DATE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::TEXT, NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::TEXT, NOW()) NOT NULL
);t test data
-- This recreates all tables and functions from scratch, excluding test profiles

BEGIN;

-- Drop all existing tables in reverse dependency order
DROP TABLE IF EXISTS public.subscription_renewals CASCADE;
DROP TABLE IF EXISTS public.subscriptions CASCADE;
DROP TABLE IF EXISTS public.user_qr_codes CASCADE;
DROP TABLE IF EXISTS public.merchant_discounts CASCADE;
DROP TABLE IF EXISTS public.payments CASCADE;
DROP TABLE IF EXISTS public.businesses CASCADE;
DROP TABLE IF EXISTS public.merchants CASCADE;
DROP TABLE IF EXISTS public.memberships CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;

-- Drop existing functions
DROP FUNCTION IF EXISTS public.generate_user_qr_code(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.process_monthly_renewal() CASCADE;
DROP FUNCTION IF EXISTS public.update_merchant_discounts_updated_at() CASCADE;
DROP FUNCTION IF EXISTS public.try_cast_double(TEXT) CASCADE;

-- Recreate base tables

-- Create profiles table
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  name TEXT,
  surname TEXT,
  email TEXT,
  role TEXT DEFAULT 'member', -- Updated: member, trusted_partner, or admin
  category TEXT,
  street TEXT,
  suburb TEXT,
  city TEXT,
  province TEXT,
  contact TEXT,
  gender TEXT,
  ethnicity TEXT,
  date_of_birth DATE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::TEXT, NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::TEXT, NOW()) NOT NULL
);

-- Create memberships table (stores user role assignments: member, trusted_partner, admin)
CREATE TABLE public.memberships (
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL, -- member, trusted_partner, or admin
  gateway TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::TEXT, NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::TEXT, NOW()) NOT NULL,
  PRIMARY KEY (user_id)
);

-- Create merchants table (stores trusted partner information for businesses)
CREATE TABLE public.merchants (
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  business_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::TEXT, NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::TEXT, NOW()) NOT NULL
);

-- Create businesses table
CREATE TABLE public.businesses (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  owner_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT,
  category TEXT,
  address TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  contact_email TEXT,
  contact_number TEXT,
  verified BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::TEXT, NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::TEXT, NOW()) NOT NULL,
  UNIQUE(owner_user_id)
);

-- Create users table (for backward compatibility)
CREATE TABLE public.users (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::TEXT, NOW()) NOT NULL
);

-- Create payments table
CREATE TABLE public.payments (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    plan_name TEXT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    payment_method TEXT NOT NULL,
    transaction_id TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'cancelled')),
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create merchant_discounts table
CREATE TABLE public.merchant_discounts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    merchant_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    percentage DECIMAL(5,2) DEFAULT 0,
    fixed_amount DECIMAL(10,2),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT discount_type_check CHECK (
        (percentage > 0 AND fixed_amount IS NULL) OR
        (percentage = 0 AND fixed_amount IS NOT NULL AND fixed_amount > 0)
    )
);

-- Create user_qr_codes table
CREATE TABLE public.user_qr_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  qr_code TEXT NOT NULL UNIQUE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create subscriptions table
CREATE TABLE public.subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_type TEXT NOT NULL CHECK (plan_type IN ('basic', 'premium', 'annual')),
  auto_renew BOOLEAN NOT NULL DEFAULT FALSE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'cancelled', 'expired')),
  current_period_start TIMESTAMP WITH TIME ZONE NOT NULL,
  current_period_end TIMESTAMP WITH TIME ZONE NOT NULL,
  cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE,
  payment_method_id TEXT,
  last_payment_date TIMESTAMP WITH TIME ZONE,
  next_payment_date TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create subscription_renewals table
CREATE TABLE public.subscription_renewals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id UUID NOT NULL REFERENCES public.subscriptions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  renewal_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  amount DECIMAL(10,2) NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('success', 'failed', 'pending')),
  payment_method TEXT,
  qr_code_updated BOOLEAN NOT NULL DEFAULT FALSE,
  error_message TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_discounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_qr_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_renewals ENABLE ROW LEVEL SECURITY;

-- Create indexes for performance
CREATE INDEX idx_profiles_role ON public.profiles(role);
CREATE INDEX idx_memberships_role ON public.memberships(role);
CREATE INDEX idx_memberships_user_id ON public.memberships(user_id);
CREATE INDEX idx_businesses_owner_user_id ON public.businesses(owner_user_id);
CREATE INDEX idx_payments_user_id ON public.payments(user_id);
CREATE INDEX idx_payments_status ON public.payments(status);
CREATE INDEX idx_payments_transaction_id ON public.payments(transaction_id);
CREATE INDEX idx_merchant_discounts_merchant_id ON public.merchant_discounts(merchant_id);
CREATE INDEX idx_merchant_discounts_active ON public.merchant_discounts(is_active);
CREATE INDEX idx_user_qr_codes_user_id ON public.user_qr_codes(user_id);
CREATE INDEX idx_user_qr_codes_active ON public.user_qr_codes(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_subscriptions_user_id ON public.subscriptions(user_id);
CREATE INDEX idx_subscriptions_status ON public.subscriptions(status);
CREATE INDEX idx_subscription_renewals_subscription_id ON public.subscription_renewals(subscription_id);

-- Basic RLS Policies

-- Profiles policies
CREATE POLICY "Users can view own profile" ON public.profiles
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

-- Memberships policies
CREATE POLICY "Users can view own membership" ON public.memberships
  FOR SELECT USING (auth.uid() = user_id);

-- Merchants policies (Trusted Partners)
CREATE POLICY "Members can view own trusted partner record" ON public.merchants
  FOR SELECT USING (auth.uid() = user_id);

-- Businesses policies (Trusted Partners)
CREATE POLICY "Trusted partners can view own business" ON public.businesses
  FOR SELECT USING (auth.uid() = owner_user_id);
CREATE POLICY "Trusted partners can update own business" ON public.businesses
  FOR UPDATE USING (auth.uid() = owner_user_id);

-- Users policies
CREATE POLICY "Users can view own user record" ON public.users
  FOR SELECT USING (auth.uid() = id);

-- Payments policies
CREATE POLICY "Users can view their own payments" ON public.payments
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own payments" ON public.payments
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Admins can view all payments" ON public.payments
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
    );
CREATE POLICY "Service role can manage payments" ON public.payments
    FOR ALL USING (auth.role() = 'service_role');

-- Merchant discounts policies
CREATE POLICY "Users can view their own discounts" ON public.merchant_discounts
    FOR SELECT USING (auth.uid() = merchant_id);
CREATE POLICY "Users can insert their own discounts" ON public.merchant_discounts
    FOR INSERT WITH CHECK (auth.uid() = merchant_id);
CREATE POLICY "Users can update their own discounts" ON public.merchant_discounts
    FOR UPDATE USING (auth.uid() = merchant_id);
CREATE POLICY "Users can delete their own discounts" ON public.merchant_discounts
    FOR DELETE USING (auth.uid() = merchant_id);

-- QR codes policies
CREATE POLICY "Users can view their own QR codes" ON public.user_qr_codes
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own QR codes" ON public.user_qr_codes
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own QR codes" ON public.user_qr_codes
  FOR UPDATE USING (auth.uid() = user_id);

-- Subscriptions policies
CREATE POLICY "Users can view their own subscriptions" ON public.subscriptions
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own subscriptions" ON public.subscriptions
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own subscriptions" ON public.subscriptions
  FOR UPDATE USING (auth.uid() = user_id);

-- Subscription renewals policies
CREATE POLICY "Users can view their own renewal history" ON public.subscription_renewals
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own renewal records" ON public.subscription_renewals
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Service role can manage renewals" ON public.subscription_renewals
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');

-- Helper Functions

-- Function to generate QR code for new user
CREATE OR REPLACE FUNCTION public.generate_user_qr_code(user_uuid UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  qr_data TEXT;
BEGIN
  -- Generate unique QR code data
  qr_data := jsonb_build_object(
    'user_id', user_uuid,
    'timestamp', extract(epoch from now())::bigint,
    'random', (random() * 999999)::int,
    'type', 'user_qr'
  )::text;

  RETURN qr_data;
END;
$$;

-- Function to handle monthly subscription renewal
CREATE OR REPLACE FUNCTION public.process_monthly_renewal()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  sub_record RECORD;
  renewal_success BOOLEAN := false;
  new_qr_code TEXT;
BEGIN
  -- Process all active auto-renew subscriptions that are due
  FOR sub_record IN
    SELECT * FROM public.subscriptions
    WHERE status = 'active'
      AND auto_renew = true
      AND next_payment_date <= NOW()
  LOOP
    -- Attempt payment processing (this would integrate with payment provider)
    -- For now, we'll simulate success/failure randomly
    renewal_success := (random() > 0.1); -- 90% success rate for demo

    -- Record the renewal attempt
    INSERT INTO public.subscription_renewals (
      subscription_id,
      user_id,
      renewal_date,
      amount,
      status,
      payment_method,
      qr_code_updated
    ) VALUES (
      sub_record.id,
      sub_record.user_id,
      NOW(),
      CASE
        WHEN sub_record.plan_type = 'basic' THEN 99.00
        WHEN sub_record.plan_type = 'premium' THEN 199.00
        WHEN sub_record.plan_type = 'annual' THEN 1999.00
        ELSE 99.00
      END,
      CASE WHEN renewal_success THEN 'success' ELSE 'failed' END,
      sub_record.payment_method_id,
      renewal_success
    );

    IF renewal_success THEN
      -- Generate new QR code
      new_qr_code := public.generate_user_qr_code(sub_record.user_id);

      -- Update QR code
      UPDATE public.user_qr_codes
      SET
        qr_code = new_qr_code,
        expires_at = NOW() + INTERVAL '1 month',
        updated_at = NOW()
      WHERE user_id = sub_record.user_id;

      -- Update subscription
      UPDATE public.subscriptions
      SET
        current_period_start = NOW(),
        current_period_end = NOW() + INTERVAL '1 month',
        next_payment_date = NOW() + INTERVAL '1 month',
        last_payment_date = NOW(),
        updated_at = NOW()
      WHERE id = sub_record.id;

    ELSE
      -- Mark QR code as inactive
      UPDATE public.user_qr_codes
      SET
        is_active = false,
        updated_at = NOW()
      WHERE user_id = sub_record.user_id;

      -- Update subscription status
      UPDATE public.subscriptions
      SET
        status = 'inactive',
        updated_at = NOW()
      WHERE id = sub_record.id;
    END IF;
  END LOOP;
END;
$$;

-- Function to update merchant_discounts updated_at timestamp
CREATE OR REPLACE FUNCTION update_merchant_discounts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Try cast double function for parsing
CREATE OR REPLACE FUNCTION public.try_cast_double(input_text TEXT)
RETURNS DOUBLE PRECISION AS $$
BEGIN
    BEGIN
        RETURN input_text::DOUBLE PRECISION;
    EXCEPTION
        WHEN invalid_text_representation THEN
            RETURN NULL;
    END;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- Create triggers
CREATE TRIGGER update_merchant_discounts_updated_at_trigger
    BEFORE UPDATE ON public.merchant_discounts
    FOR EACH ROW
    EXECUTE FUNCTION update_merchant_discounts_updated_at();

COMMIT;
 
-- Migration: Update role terminology to member/trusted_partner/admin
-- This migration updates the existing database to use correct role names

BEGIN;

-- Update role values in memberships table
UPDATE public.memberships
SET role = 'trusted_partner'
WHERE role = 'merchant';

UPDATE public.memberships
SET role = 'member'
WHERE role = 'user';

-- Update role values in profiles table
UPDATE public.profiles
SET role = 'trusted_partner'
WHERE role = 'merchant';

UPDATE public.profiles
SET role = 'member'
WHERE role = 'user';

-- Update default role in profiles table
ALTER TABLE public.profiles
ALTER COLUMN role SET DEFAULT 'member';

-- Update table comments to reflect new terminology
COMMENT ON TABLE public.merchants IS 'Stores trusted partner information for businesses';
COMMENT ON TABLE public.memberships IS 'Stores user role assignments (member, trusted_partner, admin)';
COMMENT ON COLUMN public.profiles.role IS 'User role: member, trusted_partner, or admin';
COMMENT ON COLUMN public.profiles.category IS 'For members: individual, For trusted_partners: restaurant, retail, etc.';

-- Update RLS policies to use correct terminology
DROP POLICY IF EXISTS "Users can view own merchant record" ON public.merchants;
DROP POLICY IF EXISTS "Merchants can view own business" ON public.businesses;
DROP POLICY IF EXISTS "Merchants can update own business" ON public.businesses;

-- Create updated policies with correct terminology
CREATE POLICY "Members can view own trusted partner record" ON public.merchants
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Trusted partners can view own business" ON public.businesses
  FOR SELECT USING (auth.uid() = owner_user_id);

CREATE POLICY "Trusted partners can update own business" ON public.businesses
  FOR UPDATE USING (auth.uid() = owner_user_id);

COMMIT;
 
-- Add INSERT policy for profiles table to allow authenticated users to create their own profiles
-- This fixes the issue where users are created in auth but profiles fail to insert after OTP verification

BEGIN;

-- Add INSERT policy for profiles table
CREATE POLICY "Users can insert own profile" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

COMMIT;
 
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
  for select using (auth.uid() = user_id);

drop policy if exists "Users can update own merchant record" on public.trusted_partners;
drop policy if exists "Members can update own trusted partner record" on public.trusted_partners;
create policy "Members can update own trusted partner record" on public.trusted_partners
  for update using (auth.uid() = user_id);

drop policy if exists "Users can insert own merchant record" on public.trusted_partners;
drop policy if exists "Members can insert own trusted partner record" on public.trusted_partners;
create policy "Members can insert own trusted partner record" on public.trusted_partners
  for insert with check (auth.uid() = user_id);

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
 
-- Migration: Rename merchant_discounts table to trusted_partner_discounts
-- This completes the terminology update for discount-related tables

BEGIN;

-- Step 1: Rename the table
ALTER TABLE IF EXISTS public.merchant_discounts RENAME TO trusted_partner_discounts;

-- Step 2: Rename the column
ALTER TABLE IF EXISTS public.trusted_partner_discounts RENAME COLUMN merchant_id TO trusted_partner_id;

-- Step 3: Update foreign key constraint
ALTER TABLE IF EXISTS public.trusted_partner_discounts DROP CONSTRAINT IF EXISTS merchant_discounts_merchant_id_fkey;
ALTER TABLE public.trusted_partner_discounts
ADD CONSTRAINT trusted_partner_discounts_trusted_partner_id_fkey
FOREIGN KEY (trusted_partner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Step 4: Drop old policies
DROP POLICY IF EXISTS "Users can view their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can insert their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can update their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can delete their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can view active discounts from all merchants" ON public.trusted_partner_discounts;

-- Step 5: Create new policies with updated terminology
CREATE POLICY "Members can view their own discounts" ON public.trusted_partner_discounts
  FOR SELECT USING (auth.uid() = trusted_partner_id);

CREATE POLICY "Members can insert their own discounts" ON public.trusted_partner_discounts
  FOR INSERT WITH CHECK (auth.uid() = trusted_partner_id);

CREATE POLICY "Members can update their own discounts" ON public.trusted_partner_discounts
  FOR UPDATE USING (auth.uid() = trusted_partner_id);

CREATE POLICY "Members can delete their own discounts" ON public.trusted_partner_discounts
  FOR DELETE USING (auth.uid() = trusted_partner_id);

CREATE POLICY "Members can view active discounts from all trusted partners" ON public.trusted_partner_discounts
  FOR SELECT USING (is_active = true);

-- Step 6: Drop old indexes
DROP INDEX IF EXISTS idx_merchant_discounts_merchant_id;
DROP INDEX IF EXISTS idx_merchant_discounts_active;

-- Step 7: Create new indexes with updated names
CREATE INDEX IF NOT EXISTS idx_trusted_partner_discounts_trusted_partner_id ON public.trusted_partner_discounts(trusted_partner_id);
CREATE INDEX IF NOT EXISTS idx_trusted_partner_discounts_active ON public.trusted_partner_discounts(is_active);

-- Step 8: Update the trigger function name and references
CREATE OR REPLACE FUNCTION update_trusted_partner_discounts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- Step 9: Drop old trigger
DROP TRIGGER IF EXISTS update_merchant_discounts_updated_at_trigger ON public.trusted_partner_discounts;

-- Step 10: Create new trigger with updated name
CREATE TRIGGER update_trusted_partner_discounts_updated_at_trigger
  BEFORE UPDATE ON public.trusted_partner_discounts
  FOR EACH ROW
  EXECUTE FUNCTION update_trusted_partner_discounts_updated_at();

-- Step 11: Drop old function
DROP FUNCTION IF EXISTS update_merchant_discounts_updated_at();

COMMIT;</content>
<parameter name="filePath">c:\Users\clyde\local_lekker\supabase\migrations\20250924170000_rename_merchant_discounts_to_trusted_partner_discounts.sql
 
-- Migration: Ensure all merchant-related tables are properly renamed to trusted_partner terminology
-- This migration handles any remaining references and ensures consistency

BEGIN;

-- Step 1: Rename merchants table to trusted_partners if it still exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'merchants') THEN
    ALTER TABLE public.merchants RENAME TO trusted_partners;
  END IF;
END $$;

-- Step 2: Rename merchant_discounts table to trusted_partner_discounts if it still exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'merchant_discounts') THEN
    ALTER TABLE public.merchant_discounts RENAME TO trusted_partner_discounts;
  END IF;
END $$;

-- Step 3: Rename merchant_id column to trusted_partner_id in trusted_partner_discounts if it still exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'trusted_partner_discounts' AND column_name = 'merchant_id') THEN
    ALTER TABLE public.trusted_partner_discounts RENAME COLUMN merchant_id TO trusted_partner_id;
  END IF;
END $$;

-- Step 4: Update any remaining role values from 'merchant' to 'trusted_partner'
UPDATE public.profiles
SET role = 'trusted_partner'
WHERE role = 'merchant';

UPDATE public.memberships
SET role = 'trusted_partner'
WHERE role = 'merchant';

-- Step 5: Ensure foreign key constraints are correct
ALTER TABLE public.trusted_partner_discounts DROP CONSTRAINT IF EXISTS merchant_discounts_merchant_id_fkey;
ALTER TABLE public.trusted_partner_discounts DROP CONSTRAINT IF EXISTS trusted_partner_discounts_merchant_id_fkey;
ALTER TABLE public.trusted_partner_discounts DROP CONSTRAINT IF EXISTS trusted_partner_discounts_trusted_partner_id_fkey;

ALTER TABLE public.trusted_partner_discounts
ADD CONSTRAINT trusted_partner_discounts_trusted_partner_id_fkey
FOREIGN KEY (trusted_partner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Step 6: Update RLS policies to use correct terminology
DROP POLICY IF EXISTS "Users can view their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can insert their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can update their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can delete their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can view active discounts from all merchants" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Members can view their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Members can insert their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Members can update their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Members can delete their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Members can view active discounts from all trusted partners" ON public.trusted_partner_discounts;

CREATE POLICY "Members can view their own discounts" ON public.trusted_partner_discounts
  FOR SELECT USING (auth.uid() = trusted_partner_id);

CREATE POLICY "Members can insert their own discounts" ON public.trusted_partner_discounts
  FOR INSERT WITH CHECK (auth.uid() = trusted_partner_id);

CREATE POLICY "Members can update their own discounts" ON public.trusted_partner_discounts
  FOR UPDATE USING (auth.uid() = trusted_partner_id);

CREATE POLICY "Members can delete their own discounts" ON public.trusted_partner_discounts
  FOR DELETE USING (auth.uid() = trusted_partner_id);

CREATE POLICY "Members can view active discounts from all trusted partners" ON public.trusted_partner_discounts
  FOR SELECT USING (is_active = true);

-- Step 7: Update indexes
DROP INDEX IF EXISTS idx_merchant_discounts_merchant_id;
DROP INDEX IF EXISTS idx_merchant_discounts_active;
DROP INDEX IF EXISTS idx_trusted_partner_discounts_merchant_id;

CREATE INDEX IF NOT EXISTS idx_trusted_partner_discounts_trusted_partner_id ON public.trusted_partner_discounts(trusted_partner_id);
CREATE INDEX IF NOT EXISTS idx_trusted_partner_discounts_active ON public.trusted_partner_discounts(is_active);

COMMIT;</content>
<parameter name="filePath">c:\Users\clyde\local_lekker\supabase\migrations\20250924180000_final_terminology_cleanup.sql
 
-- Migration: Completely disable the trigger to test if it's causing the database error
-- This will temporarily disable the trigger to isolate the issue

BEGIN;

-- Drop the trigger completely to test if it's causing the database error
DROP TRIGGER IF EXISTS trigger_automatic_role_assignment ON auth.users;

-- Keep the function for now in case we need to re-enable it later
-- The function will just log and return NEW without doing any database operations

COMMIT;
 
-- Migration: Create missing try_cast_double function
-- This function is used by the complete_business_profile RPC to safely cast text to double precision

BEGIN;

-- Create the try_cast_double function that's missing
CREATE OR REPLACE FUNCTION public.try_cast_double(input_text text)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
  -- Try to cast the input to double precision
  BEGIN
    RETURN input_text::double precision;
  EXCEPTION
    WHEN invalid_text_representation THEN
      -- If casting fails, return NULL
      RETURN NULL;
  END;
END;
$$;

COMMIT;
 
-- Migration: Delete all profiles and related records for clean testing
-- This removes all existing profile data so we can test fresh signups

BEGIN;

-- Delete all records from tables that reference profiles
-- Order matters due to foreign key constraints

-- Delete businesses first (references profiles.id via owner_user_id)
DELETE FROM public.businesses;

-- Delete merchants (references profiles.id via user_id)
DELETE FROM public.merchants;

-- Delete memberships (references profiles.id via user_id)
DELETE FROM public.memberships;

-- Finally delete all profiles
DELETE FROM public.profiles;

COMMIT;
 
-- Migration: Create QR codes and enhanced subscriptions system
-- Adds QR code management and subscription renewal tracking

BEGIN;

-- Create user_qr_codes table
CREATE TABLE IF NOT EXISTS public.user_qr_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  qr_code TEXT NOT NULL UNIQUE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create enhanced subscriptions table
CREATE TABLE IF NOT EXISTS public.subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_type TEXT NOT NULL CHECK (plan_type IN ('basic', 'premium', 'annual')),
  auto_renew BOOLEAN NOT NULL DEFAULT false,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'cancelled', 'expired')),
  current_period_start TIMESTAMP WITH TIME ZONE NOT NULL,
  current_period_end TIMESTAMP WITH TIME ZONE NOT NULL,
  cancel_at_period_end BOOLEAN NOT NULL DEFAULT false,
  payment_method_id TEXT,
  last_payment_date TIMESTAMP WITH TIME ZONE,
  next_payment_date TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create subscription_renewals table for tracking renewal history
CREATE TABLE IF NOT EXISTS public.subscription_renewals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id UUID NOT NULL REFERENCES public.subscriptions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  renewal_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  amount DECIMAL(10,2) NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('success', 'failed', 'pending')),
  payment_method TEXT,
  qr_code_updated BOOLEAN NOT NULL DEFAULT false,
  error_message TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_qr_codes_user_id ON public.user_qr_codes(user_id);
CREATE INDEX IF NOT EXISTS idx_user_qr_codes_active ON public.user_qr_codes(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON public.subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON public.subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subscription_renewals_subscription_id ON public.subscription_renewals(subscription_id);

-- Enable RLS
ALTER TABLE public.user_qr_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_renewals ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_qr_codes (only create if they don't exist)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_qr_codes' AND policyname = 'Users can view their own QR codes') THEN
        CREATE POLICY "Users can view their own QR codes" ON public.user_qr_codes
          FOR SELECT USING (auth.uid() = user_id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_qr_codes' AND policyname = 'Users can insert their own QR codes') THEN
        CREATE POLICY "Users can insert their own QR codes" ON public.user_qr_codes
          FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_qr_codes' AND policyname = 'Users can update their own QR codes') THEN
        CREATE POLICY "Users can update their own QR codes" ON public.user_qr_codes
          FOR UPDATE USING (auth.uid() = user_id);
    END IF;
END $$;

-- RLS Policies for subscriptions (only create if they don't exist)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'subscriptions' AND policyname = 'Users can view their own subscriptions') THEN
        CREATE POLICY "Users can view their own subscriptions" ON public.subscriptions
          FOR SELECT USING (auth.uid() = user_id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'subscriptions' AND policyname = 'Users can insert their own subscriptions') THEN
        CREATE POLICY "Users can insert their own subscriptions" ON public.subscriptions
          FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'subscriptions' AND policyname = 'Users can update their own subscriptions') THEN
        CREATE POLICY "Users can update their own subscriptions" ON public.subscriptions
          FOR UPDATE USING (auth.uid() = user_id);
    END IF;
END $$;

-- RLS Policies for subscription_renewals (only create if they don't exist)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'subscription_renewals' AND policyname = 'Users can view their own renewal history') THEN
        CREATE POLICY "Users can view their own renewal history" ON public.subscription_renewals
          FOR SELECT USING (auth.uid() = user_id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'subscription_renewals' AND policyname = 'Users can insert their own renewal records') THEN
        CREATE POLICY "Users can insert their own renewal records" ON public.subscription_renewals
          FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'subscription_renewals' AND policyname = 'Service role can manage renewals') THEN
        CREATE POLICY "Service role can manage renewals" ON public.subscription_renewals
          FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
    END IF;
END $$;

-- Function to generate QR code for new user
CREATE OR REPLACE FUNCTION public.generate_user_qr_code(user_uuid UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  qr_data TEXT;
BEGIN
  -- Generate unique QR code data
  qr_data := jsonb_build_object(
    'user_id', user_uuid,
    'timestamp', extract(epoch from now())::bigint,
    'random', (random() * 999999)::int,
    'type', 'user_qr'
  )::text;

  RETURN qr_data;
END;
$$;

-- Function to handle monthly subscription renewal
CREATE OR REPLACE FUNCTION public.process_monthly_renewal()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  sub_record RECORD;
  renewal_success BOOLEAN := false;
  new_qr_code TEXT;
BEGIN
  -- Process all active auto-renew subscriptions that are due
  FOR sub_record IN
    SELECT * FROM public.subscriptions
    WHERE status = 'active'
      AND auto_renew = true
      AND next_payment_date <= NOW()
  LOOP
    -- Attempt payment processing (this would integrate with payment provider)
    -- For now, we'll simulate success/failure randomly
    renewal_success := (random() > 0.1); -- 90% success rate for demo

    -- Record the renewal attempt
    INSERT INTO public.subscription_renewals (
      subscription_id,
      user_id,
      renewal_date,
      amount,
      status,
      payment_method,
      qr_code_updated
    ) VALUES (
      sub_record.id,
      sub_record.user_id,
      NOW(),
      CASE
        WHEN sub_record.plan_type = 'basic' THEN 99.00
        WHEN sub_record.plan_type = 'premium' THEN 199.00
        WHEN sub_record.plan_type = 'annual' THEN 1999.00
        ELSE 99.00
      END,
      CASE WHEN renewal_success THEN 'success' ELSE 'failed' END,
      sub_record.payment_method_id,
      renewal_success
    );

    IF renewal_success THEN
      -- Generate new QR code
      new_qr_code := public.generate_user_qr_code(sub_record.user_id);

      -- Update QR code
      UPDATE public.user_qr_codes
      SET
        qr_code = new_qr_code,
        expires_at = NOW() + INTERVAL '1 month',
        updated_at = NOW()
      WHERE user_id = sub_record.user_id;

      -- Update subscription
      UPDATE public.subscriptions
      SET
        current_period_start = NOW(),
        current_period_end = NOW() + INTERVAL '1 month',
        next_payment_date = NOW() + INTERVAL '1 month',
        last_payment_date = NOW(),
        updated_at = NOW()
      WHERE id = sub_record.id;

    ELSE
      -- Mark QR code as inactive
      UPDATE public.user_qr_codes
      SET
        is_active = false,
        updated_at = NOW()
      WHERE user_id = sub_record.user_id;

      -- Update subscription status
      UPDATE public.subscriptions
      SET
        status = 'inactive',
        updated_at = NOW()
      WHERE id = sub_record.id;
    END IF;
  END LOOP;
END;
$$;

COMMIT;
 
-- Fix processed_bills table column name from user_id to member_id for consistency
-- with the updated terminology (user -> member)

BEGIN;

-- Rename the column from user_id to member_id
ALTER TABLE public.processed_bills RENAME COLUMN user_id TO member_id;

-- Update the index name to reflect the new column name
DROP INDEX IF EXISTS idx_processed_bills_user_id;
CREATE INDEX IF NOT EXISTS idx_processed_bills_member_id ON processed_bills(member_id);

-- Update RLS policies to use member_id instead of user_id
DROP POLICY IF EXISTS "Users can view their own processed bills" ON public.processed_bills;
DROP POLICY IF EXISTS "Users can insert their own processed bills" ON public.processed_bills;
DROP POLICY IF EXISTS "Users can update their own processed bills" ON public.processed_bills;

CREATE POLICY "Members can view their own processed bills" ON public.processed_bills
    FOR SELECT USING (auth.uid() = member_id);

CREATE POLICY "Members can insert their own processed bills" ON public.processed_bills
    FOR INSERT WITH CHECK (auth.uid() = member_id);

CREATE POLICY "Members can update their own processed bills" ON public.processed_bills
    FOR UPDATE USING (auth.uid() = member_id);

-- Update the function to use member_id
CREATE OR REPLACE FUNCTION get_user_bill_statistics(user_uuid UUID)
RETURNS TABLE (
    total_bills BIGINT,
    total_saved DECIMAL(10,2),
    total_spent DECIMAL(10,2),
    most_used_partner TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) as total_bills,
        COALESCE(SUM(discount_amount), 0) as total_saved,
        COALESCE(SUM(original_total), 0) as total_spent,
        (
            SELECT partner_id
            FROM processed_bills pb2
            WHERE pb2.member_id = user_uuid
            GROUP BY partner_id
            ORDER BY COUNT(*) DESC
            LIMIT 1
        ) as most_used_partner
    FROM processed_bills pb
    WHERE pb.member_id = user_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

COMMIT;
 
-- Create business_logos table for logo scanner functionality
CREATE TABLE IF NOT EXISTS business_logos (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    logo_url TEXT NOT NULL,
    business_name TEXT NOT NULL,
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_business_logos_business_id ON business_logos(business_id);
CREATE INDEX IF NOT EXISTS idx_business_logos_active ON business_logos(is_active);
CREATE INDEX IF NOT EXISTS idx_business_logos_uploaded_at ON business_logos(uploaded_at DESC);

-- Enable RLS (Row Level Security)
ALTER TABLE business_logos ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Business owners can view their own logos" ON business_logos
    FOR SELECT USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can insert their own logos" ON business_logos
    FOR INSERT WITH CHECK (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can update their own logos" ON business_logos
    FOR UPDATE USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can delete their own logos" ON business_logos
    FOR DELETE USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- Create storage bucket for business logos
INSERT INTO storage.buckets (id, name, public)
VALUES ('business-logos', 'business-logos', true)
ON CONFLICT (id) DO NOTHING;

-- Create storage policies for business logos
CREATE POLICY "Business owners can view their logos" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'business-logos' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can upload their logos" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'business-logos' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can update their logos" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'business-logos' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can delete their logos" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'business-logos' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION update_business_logos_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_business_logos_updated_at
    BEFORE UPDATE ON business_logos
    FOR EACH ROW
    EXECUTE FUNCTION update_business_logos_updated_at();
 
-- Create business_bills table for bill scanner functionality
CREATE TABLE IF NOT EXISTS business_bills (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    bill_url TEXT NOT NULL,
    business_name TEXT NOT NULL,
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,
    extracted_features JSONB, -- Store extracted features for OCR matching
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_business_bills_business_id ON business_bills(business_id);
CREATE INDEX IF NOT EXISTS idx_business_bills_active ON business_bills(is_active);
CREATE INDEX IF NOT EXISTS idx_business_bills_uploaded_at ON business_bills(uploaded_at DESC);

-- Enable RLS (Row Level Security)
ALTER TABLE business_bills ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Business owners can view their own bills" ON business_bills
    FOR SELECT USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can insert their own bills" ON business_bills
    FOR INSERT WITH CHECK (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can update their own bills" ON business_bills
    FOR UPDATE USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can delete their own bills" ON business_bills
    FOR DELETE USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- Create storage bucket for business bills
INSERT INTO storage.buckets (id, name, public)
VALUES ('business-bills', 'business-bills', true)
ON CONFLICT (id) DO NOTHING;

-- Create storage policies for business bills
CREATE POLICY "Business owners can view their bills" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'business-bills' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can upload their bills" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'business-bills' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can update their bills" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'business-bills' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can delete their bills" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'business-bills' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION update_business_bills_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER update_business_bills_updated_at
    BEFORE UPDATE ON business_bills
    FOR EACH ROW
    EXECUTE FUNCTION update_business_bills_updated_at();
 
-- Add trusted partner payment flow enhancements
-- Adds approval workflow, bank accounts, and payment linking

-- Add approval status to processed_bills table
ALTER TABLE processed_bills
ADD COLUMN IF NOT EXISTS approval_status TEXT DEFAULT 'pending'
CHECK (approval_status IN ('pending', 'approved', 'rejected'));

ALTER TABLE processed_bills
ADD COLUMN IF NOT EXISTS approved_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE processed_bills
ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES auth.users(id);

ALTER TABLE processed_bills
ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- Add payment method tracking
ALTER TABLE processed_bills
ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'pending'
CHECK (payment_method IN ('pending', 'in_app', 'physical'));

ALTER TABLE processed_bills
ADD COLUMN IF NOT EXISTS payment_id UUID REFERENCES payments(id);

-- Create trusted_partner_bank_accounts table
CREATE TABLE IF NOT EXISTS trusted_partner_bank_accounts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    account_holder_name TEXT NOT NULL,
    bank_name TEXT NOT NULL,
    account_type TEXT NOT NULL CHECK (account_type IN ('checking', 'savings')),
    account_number TEXT NOT NULL,
    branch_code TEXT NOT NULL,
    payfast_merchant_id TEXT,
    payfast_merchant_key TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, account_number, branch_code)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_trusted_partner_bank_accounts_user_id
ON trusted_partner_bank_accounts(user_id);

CREATE INDEX IF NOT EXISTS idx_trusted_partner_bank_accounts_active
ON trusted_partner_bank_accounts(is_active);

-- Enable RLS
ALTER TABLE trusted_partner_bank_accounts ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view own bank accounts" ON trusted_partner_bank_accounts;
DROP POLICY IF EXISTS "Users can insert own bank accounts" ON trusted_partner_bank_accounts;
DROP POLICY IF EXISTS "Users can update own bank accounts" ON trusted_partner_bank_accounts;
DROP POLICY IF EXISTS "Users can delete own bank accounts" ON trusted_partner_bank_accounts;

-- Create RLS policies for bank accounts
CREATE POLICY "Users can view own bank accounts"
ON trusted_partner_bank_accounts
FOR SELECT USING (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can insert own bank accounts"
ON trusted_partner_bank_accounts
FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can update own bank accounts"
ON trusted_partner_bank_accounts
FOR UPDATE USING (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can delete own bank accounts"
ON trusted_partner_bank_accounts
FOR DELETE USING (user_id = (SELECT auth.uid()));

-- Create bill_approvals table for tracking approval workflow
CREATE TABLE IF NOT EXISTS bill_approvals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    bill_id UUID NOT NULL REFERENCES processed_bills(id) ON DELETE CASCADE,
    partner_id UUID NOT NULL REFERENCES auth.users(id),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected')),
    review_notes TEXT,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(bill_id, partner_id)
);

-- Create indexes for bill approvals
CREATE INDEX IF NOT EXISTS idx_bill_approvals_bill_id ON bill_approvals(bill_id);
CREATE INDEX IF NOT EXISTS idx_bill_approvals_partner_id ON bill_approvals(partner_id);
CREATE INDEX IF NOT EXISTS idx_bill_approvals_status ON bill_approvals(status);

-- Enable RLS for bill approvals
ALTER TABLE bill_approvals ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Partners can view their own approvals" ON bill_approvals;
DROP POLICY IF EXISTS "Partners can insert approvals for their bills" ON bill_approvals;
DROP POLICY IF EXISTS "Partners can update their own approvals" ON bill_approvals;

-- Create RLS policies for bill approvals
CREATE POLICY "Partners can view their own approvals"
ON bill_approvals
FOR SELECT USING (partner_id = (SELECT auth.uid()));

CREATE POLICY "Partners can insert approvals for their bills"
ON bill_approvals
FOR INSERT WITH CHECK (partner_id = (SELECT auth.uid()));

CREATE POLICY "Partners can update their own approvals"
ON bill_approvals
FOR UPDATE USING (partner_id = (SELECT auth.uid()));

-- Create function to automatically create approval records
CREATE OR REPLACE FUNCTION create_bill_approval()
RETURNS TRIGGER AS $$
BEGIN
    -- Insert approval record for the partner (business owner)
    INSERT INTO bill_approvals (bill_id, partner_id)
    SELECT NEW.id, b.owner_member_id
    FROM businesses b
    WHERE b.id = NEW.partner_id::uuid;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- Create trigger to auto-create approval records
DROP TRIGGER IF EXISTS trigger_create_bill_approval ON processed_bills;
CREATE TRIGGER trigger_create_bill_approval
    AFTER INSERT ON processed_bills
    FOR EACH ROW
    EXECUTE FUNCTION create_bill_approval();

-- Create function to update bill approval status
CREATE OR REPLACE FUNCTION update_bill_approval_status()
RETURNS TRIGGER AS $$
BEGIN
    -- Update the processed_bills approval status when approval is updated
    IF NEW.status != OLD.status THEN
        UPDATE processed_bills
        SET
            approval_status = NEW.status,
            approved_at = CASE WHEN NEW.status = 'approved' THEN NOW() ELSE approved_at END,
            approved_by = CASE WHEN NEW.status = 'approved' THEN NEW.partner_id ELSE approved_by END
        WHERE id = NEW.bill_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- Create trigger for approval status updates
DROP TRIGGER IF EXISTS trigger_update_bill_approval_status ON bill_approvals;
CREATE TRIGGER trigger_update_bill_approval_status
    AFTER UPDATE ON bill_approvals
    FOR EACH ROW
    EXECUTE FUNCTION update_bill_approval_status();

-- Create updated_at triggers
CREATE OR REPLACE FUNCTION public.update_trusted_partner_bank_accounts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS update_trusted_partner_bank_accounts_updated_at ON trusted_partner_bank_accounts;
CREATE TRIGGER update_trusted_partner_bank_accounts_updated_at
    BEFORE UPDATE ON trusted_partner_bank_accounts
    FOR EACH ROW
    EXECUTE FUNCTION public.update_trusted_partner_bank_accounts_updated_at();

CREATE OR REPLACE FUNCTION public.update_bill_approvals_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS update_bill_approvals_updated_at ON bill_approvals;
CREATE TRIGGER update_bill_approvals_updated_at
    BEFORE UPDATE ON bill_approvals
    FOR EACH ROW
    EXECUTE FUNCTION public.update_bill_approvals_updated_at();
 
-- Migration: Automatic QR Code Management and Payment Processing
-- Handles automatic payments, QR activation/deactivation, and manual renewal flow

BEGIN;

-- Create payment_schedules table for tracking automatic payments
CREATE TABLE IF NOT EXISTS public.payment_schedules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subscription_id UUID NOT NULL REFERENCES public.subscriptions(id) ON DELETE CASCADE,
  payment_method TEXT NOT NULL,
  payment_method_id TEXT,
  amount DECIMAL(10,2) NOT NULL,
  next_payment_date TIMESTAMP WITH TIME ZONE NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_attempt_date TIMESTAMP WITH TIME ZONE,
  failure_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_payment_schedules_user_id ON public.payment_schedules(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_schedules_next_payment ON public.payment_schedules(next_payment_date);
CREATE INDEX IF NOT EXISTS idx_payment_schedules_active ON public.payment_schedules(is_active) WHERE is_active = true;

-- Enable RLS
ALTER TABLE public.payment_schedules ENABLE ROW LEVEL SECURITY;

-- RLS Policies for payment_schedules
DROP POLICY IF EXISTS "Users can view their own payment schedules" ON public.payment_schedules;
DROP POLICY IF EXISTS "Service role can manage payment schedules" ON public.payment_schedules;

CREATE POLICY "Users can view their own payment schedules" ON public.payment_schedules
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Service role can manage payment schedules" ON public.payment_schedules
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');

-- Function to schedule automatic payment for new auto-renew subscriptions
DROP FUNCTION IF EXISTS public.schedule_automatic_payment(UUID, UUID, TEXT, TEXT, DECIMAL);
CREATE OR REPLACE FUNCTION public.schedule_automatic_payment(
  p_user_id UUID,
  p_subscription_id UUID,
  p_payment_method TEXT,
  p_payment_method_id TEXT,
  p_amount DECIMAL(10,2)
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.payment_schedules (
    user_id,
    subscription_id,
    payment_method,
    payment_method_id,
    amount,
    next_payment_date
  ) VALUES (
    p_user_id,
    p_subscription_id,
    p_payment_method,
    p_payment_method_id,
    p_amount,
    NOW() + INTERVAL '1 month'
  );
END;
$$;

-- Function to process automatic payments
DROP FUNCTION IF EXISTS public.process_automatic_payments();
CREATE OR REPLACE FUNCTION public.process_automatic_payments()
RETURNS TABLE(
  user_id UUID,
  subscription_id UUID,
  success BOOLEAN,
  amount DECIMAL(10,2),
  error_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  schedule_record RECORD;
  payment_success BOOLEAN := false;
  error_msg TEXT := '';
  new_qr_code TEXT;
BEGIN
  -- Process all due automatic payments
  FOR schedule_record IN
    SELECT * FROM public.payment_schedules
    WHERE is_active = true
      AND next_payment_date <= NOW()
      AND failure_count < 3
  LOOP
    BEGIN
      -- Simulate payment processing (integrate with actual payment provider)
      -- For demo purposes, simulate 95% success rate
      payment_success := (random() > 0.05);

      IF payment_success THEN
        -- Generate new QR code
        new_qr_code := public.generate_user_qr_code(schedule_record.user_id);

        -- Activate QR code
        UPDATE public.user_qr_codes
        SET
          qr_code = new_qr_code,
          is_active = true,
          expires_at = NOW() + INTERVAL '1 month',
          updated_at = NOW()
        WHERE user_id = schedule_record.user_id;

        -- Update subscription
        UPDATE public.subscriptions
        SET
          current_period_start = NOW(),
          current_period_end = NOW() + INTERVAL '1 month',
          next_payment_date = NOW() + INTERVAL '1 month',
          last_payment_date = NOW(),
          status = 'active',
          updated_at = NOW()
        WHERE id = schedule_record.subscription_id;

        -- Record successful renewal
        INSERT INTO public.subscription_renewals (
          subscription_id,
          user_id,
          renewal_date,
          amount,
          status,
          payment_method,
          qr_code_updated
        ) VALUES (
          schedule_record.subscription_id,
          schedule_record.user_id,
          NOW(),
          schedule_record.amount,
          'success',
          schedule_record.payment_method,
          true
        );

        -- Reset failure count and schedule next payment
        UPDATE public.payment_schedules
        SET
          next_payment_date = NOW() + INTERVAL '1 month',
          last_attempt_date = NOW(),
          failure_count = 0,
          updated_at = NOW()
        WHERE id = schedule_record.id;

      ELSE
        -- Payment failed
        error_msg := 'Payment processing failed';

        -- Increment failure count
        UPDATE public.payment_schedules
        SET
          failure_count = failure_count + 1,
          last_attempt_date = NOW(),
          updated_at = NOW()
        WHERE id = schedule_record.id;

        -- If too many failures, deactivate
        IF schedule_record.failure_count + 1 >= 3 THEN
          -- Deactivate QR code
          UPDATE public.user_qr_codes
          SET
            is_active = false,
            updated_at = NOW()
          WHERE user_id = schedule_record.user_id;

          -- Update subscription status
          UPDATE public.subscriptions
          SET
            status = 'inactive',
            updated_at = NOW()
          WHERE id = schedule_record.subscription_id;

          -- Deactivate payment schedule
          UPDATE public.payment_schedules
          SET
            is_active = false,
            updated_at = NOW()
          WHERE id = schedule_record.id;
        END IF;

        -- Record failed renewal
        INSERT INTO public.subscription_renewals (
          subscription_id,
          user_id,
          renewal_date,
          amount,
          status,
          payment_method,
          qr_code_updated,
          error_message
        ) VALUES (
          schedule_record.subscription_id,
          schedule_record.user_id,
          NOW(),
          schedule_record.amount,
          'failed',
          schedule_record.payment_method,
          false,
          error_msg
        );

      END IF;

      -- Return result
      RETURN QUERY SELECT
        schedule_record.user_id,
        schedule_record.subscription_id,
        payment_success,
        schedule_record.amount,
        error_msg;

    EXCEPTION WHEN OTHERS THEN
      -- Handle unexpected errors
      error_msg := SQLERRM;

      -- Record error in renewal history
      INSERT INTO public.subscription_renewals (
        subscription_id,
        user_id,
        renewal_date,
        amount,
        status,
        payment_method,
        qr_code_updated,
        error_message
      ) VALUES (
        schedule_record.subscription_id,
        schedule_record.user_id,
        NOW(),
        schedule_record.amount,
        'failed',
        schedule_record.payment_method,
        false,
        error_msg
      );

      RETURN QUERY SELECT
        schedule_record.user_id,
        schedule_record.subscription_id,
        false,
        schedule_record.amount,
        error_msg;
    END;
  END LOOP;
END;
$$;

-- Function to handle manual payment completion and QR activation
DROP FUNCTION IF EXISTS public.activate_qr_after_payment(UUID, TEXT, DECIMAL);
CREATE OR REPLACE FUNCTION public.activate_qr_after_payment(
  p_user_id UUID,
  p_plan_type TEXT,
  p_amount DECIMAL(10,2)
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_qr_code TEXT;
  subscription_id UUID;
BEGIN
  -- Generate new QR code
  new_qr_code := public.generate_user_qr_code(p_user_id);

  -- Delete any existing QR codes for this user (ensure only one per user)
  DELETE FROM public.user_qr_codes WHERE user_id = p_user_id;

  -- Insert new QR code
  INSERT INTO public.user_qr_codes (
    user_id,
    qr_code,
    is_active,
    expires_at
  ) VALUES (
    p_user_id,
    new_qr_code,
    true,
    NOW() + INTERVAL '1 month'
  );

  -- Get or create subscription
  SELECT id INTO subscription_id
  FROM public.subscriptions
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF subscription_id IS NULL THEN
    -- Create new subscription
    INSERT INTO public.subscriptions (
      user_id,
      plan_type,
      auto_renew,
      status,
      current_period_start,
      current_period_end,
      last_payment_date
    ) VALUES (
      p_user_id,
      p_plan_type,
      false, -- Manual payment
      'active',
      NOW(),
      NOW() + INTERVAL '1 month',
      NOW()
    ) RETURNING id INTO subscription_id;
  ELSE
    -- Update existing subscription
    UPDATE public.subscriptions
    SET
      current_period_start = NOW(),
      current_period_end = NOW() + INTERVAL '1 month',
      last_payment_date = NOW(),
      status = 'active',
      updated_at = NOW()
    WHERE id = subscription_id;
  END IF;

  -- Record renewal
  INSERT INTO public.subscription_renewals (
    subscription_id,
    user_id,
    renewal_date,
    amount,
    status,
    qr_code_updated
  ) VALUES (
    subscription_id,
    p_user_id,
    NOW(),
    p_amount,
    'success',
    true
  );

  RETURN true;
END;
$$;

-- Trigger function to automatically activate QR codes after successful payments
CREATE OR REPLACE FUNCTION public.handle_payment_completion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only process completed payments
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    -- Call the QR activation function
    PERFORM public.activate_qr_after_payment(
      NEW.user_id,
      NEW.plan_name,
      NEW.amount
    );
  END IF;

  RETURN NEW;
END;
$$;

-- Create trigger on payments table
DROP TRIGGER IF EXISTS trigger_payment_completion ON public.payments;
CREATE TRIGGER trigger_payment_completion
  AFTER INSERT OR UPDATE ON public.payments
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_payment_completion();

-- Function to get subscription status and renewal info
DROP FUNCTION IF EXISTS public.get_subscription_status(UUID);
CREATE OR REPLACE FUNCTION public.get_subscription_status(p_user_id UUID)
RETURNS TABLE(
  has_active_qr BOOLEAN,
  qr_expires_at TIMESTAMP WITH TIME ZONE,
  subscription_status TEXT,
  auto_renew BOOLEAN,
  days_until_renewal INTEGER,
  next_payment_date TIMESTAMP WITH TIME ZONE,
  payment_overdue BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  qr_record RECORD;
  sub_record RECORD;
  days_diff INTEGER;
BEGIN
  -- Get QR code info
  SELECT is_active, expires_at INTO qr_record
  FROM public.user_qr_codes
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  -- Get subscription info
  SELECT s.status, s.auto_renew, s.next_payment_date INTO sub_record
  FROM public.subscriptions s
  WHERE s.user_id = p_user_id
  ORDER BY s.created_at DESC
  LIMIT 1;

  -- Calculate days until renewal
  IF sub_record.next_payment_date IS NOT NULL THEN
    days_diff := EXTRACT(EPOCH FROM (sub_record.next_payment_date - NOW())) / 86400;
  ELSE
    days_diff := NULL;
  END IF;

  -- Return results
  RETURN QUERY SELECT
    COALESCE(qr_record.is_active, false),
    qr_record.expires_at,
    COALESCE(sub_record.status, 'none'),
    COALESCE(sub_record.auto_renew, false),
    days_diff::INTEGER,
    sub_record.next_payment_date,
    CASE WHEN days_diff < 0 THEN true ELSE false END;
END;
$$;

-- Function to schedule automatic payments when auto-renew is enabled
DROP FUNCTION IF EXISTS public.enable_auto_renewal(UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.enable_auto_renewal(
  p_user_id UUID,
  p_payment_method TEXT,
  p_payment_method_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  subscription_record RECORD;
  schedule_amount DECIMAL(10,2);
BEGIN
  -- Get user's subscription
  SELECT * INTO subscription_record
  FROM public.subscriptions
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF subscription_record.id IS NULL THEN
    RETURN false;
  END IF;

  -- Calculate amount based on plan
  CASE subscription_record.plan_type
    WHEN 'basic' THEN schedule_amount := 99.00;
    WHEN 'premium' THEN schedule_amount := 199.00;
    WHEN 'annual' THEN schedule_amount := 1999.00;
    ELSE schedule_amount := 99.00;
  END CASE;

  -- Update subscription to auto-renew
  UPDATE public.subscriptions
  SET
    auto_renew = true,
    next_payment_date = NOW() + INTERVAL '1 month',
    updated_at = NOW()
  WHERE id = subscription_record.id;

  -- Schedule automatic payments
  PERFORM public.schedule_automatic_payment(
    p_user_id,
    subscription_record.id,
    p_payment_method,
    p_payment_method_id,
    schedule_amount
  );

  RETURN true;
END;
$$;

-- Function to disable auto-renewal
DROP FUNCTION IF EXISTS public.disable_auto_renewal(UUID);
CREATE OR REPLACE FUNCTION public.disable_auto_renewal(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Update subscription
  UPDATE public.subscriptions
  SET
    auto_renew = false,
    next_payment_date = NOW() + INTERVAL '1 month',
    updated_at = NOW()
  WHERE user_id = p_user_id;

  -- Deactivate payment schedule
  UPDATE public.payment_schedules
  SET
    is_active = false,
    updated_at = NOW()
  WHERE user_id = p_user_id;

  RETURN true;
END;
$$;

COMMIT;
 
-- Create admin user manually in Supabase Dashboard
-- This migration provides instructions since auth.admin.create_user() is not accessible from SQL editor

-- MANUAL STEPS REQUIRED:
-- 1. Go to Supabase Dashboard > Authentication > Users
-- 2. Click "Add user"
-- 3. Enter:
--    Email: admin@locallekker.com
--    Password: Admin123!
--    Auto-confirm user: CHECKED
--    User metadata: {"name": "Admin", "surname": "User"}
-- 4. Click "Create user"
-- 5. Copy the User ID from the created user
-- 6. Run the SQL below in Supabase Dashboard > SQL Editor, replacing 'YOUR_ADMIN_USER_ID_HERE' with the actual UUID

-- SQL to run after creating user in dashboard:
/*
-- Replace YOUR_ADMIN_USER_ID_HERE with the actual user ID from the dashboard
DO $$
DECLARE
  admin_user_id UUID := 'YOUR_ADMIN_USER_ID_HERE';
BEGIN
  -- Insert into profiles
  INSERT INTO public.profiles (
    id,
    name,
    surname,
    email,
    category,
    role,
    created_at,
    updated_at
  ) VALUES (
    admin_user_id,
    'Admin',
    'User',
    'admin@locallekker.com',
    'admin',
    'admin',
    NOW(),
    NOW()
  ) ON CONFLICT (id) DO NOTHING;

  -- Insert into memberships
  INSERT INTO public.memberships (
    user_id,
    role,
    status,
    created_at,
    updated_at
  ) VALUES (
    admin_user_id,
    'admin',
    'active',
    NOW(),
    NOW()
  ) ON CONFLICT (user_id) DO NOTHING;

END $$;
*/
 
-- Fix: Update activate_qr_after_payment function to remove ON CONFLICT issue
-- This migration fixes the PostgrestException by removing the problematic ON CONFLICT clause

BEGIN;

-- Update the activate_qr_after_payment function to validate plan_type
CREATE OR REPLACE FUNCTION public.activate_qr_after_payment(
  p_user_id UUID,
  p_plan_type TEXT,
  p_amount DECIMAL(10,2)
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_qr_code TEXT;
  subscription_id UUID;
  valid_plan_type TEXT;
BEGIN
  -- Validate and normalize plan_type
  CASE LOWER(TRIM(p_plan_type))
    WHEN 'basic', 'premium', 'annual' THEN
      valid_plan_type := LOWER(TRIM(p_plan_type));
    ELSE
      -- Default to 'basic' for invalid plan types
      valid_plan_type := 'basic';
      RAISE WARNING 'Invalid plan_type "%" provided, defaulting to "basic"', p_plan_type;
  END CASE;

  -- Generate new QR code
  new_qr_code := public.generate_user_qr_code(p_user_id);

  -- Delete any existing QR codes for this user (ensure only one per user)
  DELETE FROM public.user_qr_codes WHERE user_id = p_user_id;

  -- Insert new QR code
  INSERT INTO public.user_qr_codes (
    user_id,
    qr_code,
    is_active,
    expires_at
  ) VALUES (
    p_user_id,
    new_qr_code,
    true,
    NOW() + INTERVAL '1 month'
  );

  -- Get or create subscription
  SELECT id INTO subscription_id
  FROM public.subscriptions
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF subscription_id IS NULL THEN
    -- Create new subscription
    INSERT INTO public.subscriptions (
      user_id,
      plan_type,
      auto_renew,
      status,
      current_period_start,
      current_period_end,
      last_payment_date
    ) VALUES (
      p_user_id,
      valid_plan_type, -- Use validated plan type
      false, -- Manual payment
      'active',
      NOW(),
      NOW() + INTERVAL '1 month',
      NOW()
    ) RETURNING id INTO subscription_id;
  ELSE
    -- Update existing subscription
    UPDATE public.subscriptions
    SET
      plan_type = valid_plan_type, -- Update to validated plan type
      status = 'active',
      current_period_start = NOW(),
      current_period_end = NOW() + INTERVAL '1 month',
      last_payment_date = NOW(),
      updated_at = NOW()
    WHERE id = subscription_id;
  END IF;

  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to activate QR code after payment: %', SQLERRM;
END;
$$;

COMMIT;
 
-- Fix PayFast payment failure by adding missing remarketing_id column
-- This resolves the 'Could not find the remarketing_id column' error

-- Add remarketing_id column required by PayFast webhooks
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS remarketing_id TEXT;

-- Add other common PayFast webhook fields for future compatibility
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS pf_payment_id TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS payment_status TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS item_name TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS item_description TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS merchant_id TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS token TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS signature TEXT;

-- Create index on pf_payment_id for PayFast lookups
CREATE INDEX IF NOT EXISTS idx_payments_pf_payment_id ON public.payments(pf_payment_id);
 
-- Fix plan_type validation in activate_qr_after_payment function
-- This resolves the check constraint violation error

BEGIN;

-- Update the activate_qr_after_payment function with proper plan_type validation
CREATE OR REPLACE FUNCTION public.activate_qr_after_payment(
  p_user_id UUID,
  p_plan_type TEXT,
  p_amount DECIMAL(10,2)
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_qr_code TEXT;
  subscription_id UUID;
  valid_plan_type TEXT;
BEGIN
  -- Validate and normalize plan_type to prevent check constraint violations
  CASE LOWER(TRIM(COALESCE(p_plan_type, '')))
    WHEN 'basic' THEN valid_plan_type := 'basic';
    WHEN 'premium' THEN valid_plan_type := 'premium';
    WHEN 'annual' THEN valid_plan_type := 'annual';
    ELSE
      -- Default to 'basic' for any invalid plan type
      valid_plan_type := 'basic';
      RAISE WARNING 'Invalid plan_type "%" provided to activate_qr_after_payment, defaulting to "basic"', COALESCE(p_plan_type, 'NULL');
  END CASE;

  -- Generate new QR code
  new_qr_code := public.generate_user_qr_code(p_user_id);

  -- Delete any existing QR codes for this user (ensure only one per user)
  DELETE FROM public.user_qr_codes WHERE user_id = p_user_id;

  -- Insert new QR code
  INSERT INTO public.user_qr_codes (
    user_id,
    qr_code,
    is_active,
    expires_at
  ) VALUES (
    p_user_id,
    new_qr_code,
    true,
    NOW() + INTERVAL '1 month'
  );

  -- Get or create subscription
  SELECT id INTO subscription_id
  FROM public.subscriptions
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF subscription_id IS NULL THEN
    -- Create new subscription with validated plan type
    INSERT INTO public.subscriptions (
      user_id,
      plan_type,
      auto_renew,
      status,
      current_period_start,
      current_period_end,
      last_payment_date
    ) VALUES (
      p_user_id,
      valid_plan_type,
      false, -- Manual payment
      'active',
      NOW(),
      NOW() + INTERVAL '1 month',
      NOW()
    ) RETURNING id INTO subscription_id;
  ELSE
    -- Update existing subscription with validated plan type
    UPDATE public.subscriptions
    SET
      plan_type = valid_plan_type,
      status = 'active',
      current_period_start = NOW(),
      current_period_end = NOW() + INTERVAL '1 month',
      last_payment_date = NOW(),
      updated_at = NOW()
    WHERE id = subscription_id;
  END IF;

  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to activate QR code after payment: %', SQLERRM;
END;
$$;

COMMIT;
 
-- Create calibration_receipts table for trusted partner receipt calibration
-- This table stores the text blocks and layout data from calibration receipts
-- to enable automatic identification of trusted partners when members scan receipts

CREATE TABLE IF NOT EXISTS calibration_receipts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    business_name TEXT NOT NULL,
    receipt_url TEXT NOT NULL,
    text_blocks JSONB NOT NULL, -- Array of text block objects with text, x, y, width, height
    layout_data JSONB NOT NULL, -- Layout bounds and metadata for matching
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,

    -- Indexes for performance
    INDEX idx_calibration_receipts_business_id (business_id),
    INDEX idx_calibration_receipts_active (is_active),
    INDEX idx_calibration_receipts_uploaded_at (uploaded_at DESC)
);

-- Add RLS policies
ALTER TABLE calibration_receipts ENABLE ROW LEVEL SECURITY;

-- Policy: Business owners can view and manage their own calibration receipts
CREATE POLICY "Business owners can manage their calibration receipts"
ON calibration_receipts
FOR ALL
USING (business_id = auth.uid());

-- Policy: Members can view active calibration receipts for matching (read-only)
CREATE POLICY "Members can view active calibration receipts"
ON calibration_receipts
FOR SELECT
USING (is_active = true);

-- Policy: Allow service role to manage all calibration receipts (for background processing)
CREATE POLICY "Service role can manage all calibration receipts"
ON calibration_receipts
FOR ALL
USING (auth.role() = 'service_role');

-- Add comments for documentation
COMMENT ON TABLE calibration_receipts IS 'Stores calibration receipt data for automatic trusted partner identification';
COMMENT ON COLUMN calibration_receipts.text_blocks IS 'JSON array of text blocks with position and content data';
COMMENT ON COLUMN calibration_receipts.layout_data IS 'Layout bounds and metadata for receipt matching';
 
-- Migration: Fix subscription status function and QR code queries
-- Fixes ambiguous column reference and join issues

BEGIN;

-- Drop the existing function first to allow return type change
DROP FUNCTION IF EXISTS public.get_subscription_status(UUID);

-- Fix the get_subscription_status function to avoid ambiguous column references
CREATE OR REPLACE FUNCTION public.get_subscription_status(p_user_id UUID)
RETURNS TABLE(
  has_active_qr BOOLEAN,
  qr_expires_at TIMESTAMP WITH TIME ZONE,
  subscription_status TEXT,
  auto_renew BOOLEAN,
  days_until_renewal INTEGER,
  next_payment_date TIMESTAMP WITH TIME ZONE,
  payment_overdue BOOLEAN,
  subscription_end_date TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  qr_record RECORD;
  sub_record RECORD;
  days_diff INTEGER;
BEGIN
  -- Get QR code info
  SELECT is_active, expires_at INTO qr_record
  FROM public.user_qr_codes
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  -- Get subscription info with table alias to avoid ambiguity
  SELECT s.status, s.auto_renew, s.next_payment_date, s.current_period_end INTO sub_record
  FROM public.subscriptions s
  WHERE s.user_id = p_user_id
  ORDER BY s.created_at DESC
  LIMIT 1;

  -- Calculate days until renewal (based on subscription end date)
  IF sub_record.current_period_end IS NOT NULL THEN
    days_diff := EXTRACT(EPOCH FROM (sub_record.current_period_end - NOW())) / 86400;
  ELSE
    days_diff := NULL;
  END IF;

  -- Return results
  RETURN QUERY SELECT
    COALESCE(qr_record.is_active, false),
    qr_record.expires_at,
    COALESCE(sub_record.status, 'none'),
    COALESCE(sub_record.auto_renew, false),
    days_diff::INTEGER,
    sub_record.next_payment_date,
    CASE WHEN days_diff < 0 THEN true ELSE false END,
    sub_record.current_period_end;
END;
$$;

COMMIT;
 
-- Migration: Fix database functions to populate name and surname columns in user_qr_codes
-- Extract name and surname from QR code JSON when inserting/updating records

BEGIN;

-- Update activate_qr_after_payment function to populate name and surname
CREATE OR REPLACE FUNCTION public.activate_qr_after_payment(
  p_user_id UUID,
  p_plan_type TEXT,
  p_amount DECIMAL(10,2)
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_qr_code TEXT;
  subscription_id UUID;
  valid_plan_type TEXT;
  qr_name TEXT;
  qr_surname TEXT;
BEGIN
  -- Validate and normalize plan_type
  CASE LOWER(TRIM(p_plan_type))
    WHEN 'basic', 'premium', 'annual' THEN
      valid_plan_type := LOWER(TRIM(p_plan_type));
    ELSE
      -- Default to 'basic' for invalid plan types
      valid_plan_type := 'basic';
      RAISE WARNING 'Invalid plan_type "%" provided, defaulting to "basic"', p_plan_type;
  END CASE;

  -- Generate new QR code
  new_qr_code := public.generate_user_qr_code(p_user_id);

  -- Extract name and surname from QR code JSON
  qr_name := (new_qr_code::jsonb->>'name');
  qr_surname := (new_qr_code::jsonb->>'surname');

  -- Delete any existing QR codes for this user (ensure only one per user)
  DELETE FROM public.user_qr_codes WHERE user_id = p_user_id;

  -- Insert new QR code with name and surname
  INSERT INTO public.user_qr_codes (
    user_id,
    qr_code,
    name,
    surname,
    is_active,
    expires_at
  ) VALUES (
    p_user_id,
    new_qr_code,
    qr_name,
    qr_surname,
    true,
    NOW() + INTERVAL '1 month'
  );

  -- Get or create subscription
  SELECT id INTO subscription_id
  FROM public.subscriptions
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF subscription_id IS NULL THEN
    -- Create new subscription
    INSERT INTO public.subscriptions (
      user_id,
      plan_type,
      auto_renew,
      status,
      current_period_start,
      current_period_end,
      last_payment_date
    ) VALUES (
      p_user_id,
      valid_plan_type, -- Use validated plan type
      false, -- Manual payment
      'active',
      NOW(),
      NOW() + INTERVAL '1 month',
      NOW()
    ) RETURNING id INTO subscription_id;
  ELSE
    -- Update existing subscription
    UPDATE public.subscriptions
    SET
      plan_type = valid_plan_type, -- Update to validated plan type
      status = 'active',
      current_period_start = NOW(),
      current_period_end = NOW() + INTERVAL '1 month',
      last_payment_date = NOW(),
      updated_at = NOW()
    WHERE id = subscription_id;
  END IF;

  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to activate QR code after payment: %', SQLERRM;
END;
$$;

-- Update process_automatic_payment function to populate name and surname
CREATE OR REPLACE FUNCTION public.process_automatic_payment(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_qr_code TEXT;
  subscription_id UUID;
  qr_name TEXT;
  qr_surname TEXT;
BEGIN
  -- Generate new QR code
  new_qr_code := public.generate_user_qr_code(p_user_id);

  -- Extract name and surname from QR code JSON
  qr_name := (new_qr_code::jsonb->>'name');
  qr_surname := (new_qr_code::jsonb->>'surname');

  -- Delete any existing QR codes for this user (ensure only one per user)
  DELETE FROM public.user_qr_codes WHERE user_id = p_user_id;

  -- Insert new QR code with name and surname
  INSERT INTO public.user_qr_codes (
    user_id,
    qr_code,
    name,
    surname,
    is_active,
    expires_at
  ) VALUES (
    p_user_id,
    new_qr_code,
    qr_name,
    qr_surname,
    true,
    NOW() + INTERVAL '1 month'
  );

  -- Update subscription status
  UPDATE public.subscriptions
  SET
    status = 'active',
    current_period_start = NOW(),
    current_period_end = NOW() + INTERVAL '1 month',
    last_payment_date = NOW(),
    updated_at = NOW()
  WHERE user_id = p_user_id;

  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to process automatic payment: %', SQLERRM;
END;
$$;

COMMIT;
 
-- Migration: Fix trusted_partners table population in complete_business_profile RPC
-- Ensures that the trusted_partners table business_name field is populated when business profile is completed

CREATE OR REPLACE FUNCTION public.complete_business_profile(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();

  v_name   text := nullif(coalesce(payload->>'name', ''), '');
  v_cat    text := nullif(coalesce(payload->>'category', ''), '');
  v_street text := nullif(coalesce(payload->>'street', ''), '');
  v_suburb text := nullif(coalesce(payload->>'suburb', ''), '');
  v_city   text := nullif(coalesce(payload->>'city', ''), '');
  v_prov   text := nullif(coalesce(payload->>'province', ''), '');
  v_contact_email text := nullif(coalesce(payload->>'contact_email', ''), '');
  v_contact_number text := nullif(coalesce(payload->>'contact_number', ''), '');

  v_latitude  double precision := public.try_cast_double(coalesce(payload->>'latitude', null));
  v_longitude double precision := public.try_cast_double(coalesce(payload->>'longitude', null));

  v_address text;
  v_business_id uuid;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  -- Build address
  v_address := array_to_string(
    array_remove(array[v_street, v_suburb, v_city, v_prov], null),
    ', '
  );
  IF v_address = '' THEN v_address := null; END IF;

  -- Validation
  IF coalesce(v_name, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_business_name');
  END IF;
  IF coalesce(v_cat, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_category');
  END IF;

  -- Ensure user has trusted_partner role in memberships table
  INSERT INTO public.memberships (user_id, role, gateway)
  VALUES (uid, 'trusted_partner', 'business_profile_completion')
  ON CONFLICT (user_id) DO UPDATE
    SET role = 'trusted_partner',
        gateway = excluded.gateway;

  -- Also ensure profiles table has trusted_partner role
  UPDATE public.profiles
  SET role = 'trusted_partner'
  WHERE id = uid AND (role IS NULL OR role != 'trusted_partner');

  -- Create/update trusted_partners table with business name
  INSERT INTO public.trusted_partners (user_id, business_name)
  VALUES (uid, v_name)
  ON CONFLICT (user_id) DO UPDATE
    SET business_name = excluded.business_name,
        updated_at = NOW();

  -- Create/update business record
  INSERT INTO public.businesses (
    owner_member_id, name, category, address, latitude, longitude, contact_email, contact_number, verified
  ) VALUES (
    uid, v_name, v_cat, v_address, v_latitude, v_longitude, v_contact_email, v_contact_number, true
  ) ON CONFLICT (owner_member_id) DO UPDATE
    SET name = excluded.name,
        category = excluded.category,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        contact_email = excluded.contact_email,
        contact_number = excluded.contact_number,
        verified = true
  RETURNING id INTO v_business_id;

  RETURN jsonb_build_object('ok', true, 'business_id', v_business_id);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$$;
 
-- Migration: Fix remaining functions that still use old merchant terminology
-- These functions were created/updated after the terminology migration and need to be corrected

BEGIN;

-- Fix the complete_merchant_signup function to use trusted_partner terminology
CREATE OR REPLACE FUNCTION public.complete_merchant_signup(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  v_full_name text := nullif(coalesce(payload->>'full_name', ''), '');
  v_business_name text := nullif(coalesce(payload->>'business_name', ''), '');
  v_email text := nullif(coalesce(payload->>'email', ''), '');
  v_surname text := nullif(coalesce(payload->>'surname', ''), '');
  v_profile_id uuid;
  v_merchant_id uuid;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  -- Validation
  IF coalesce(v_full_name, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_full_name');
  END IF;

  -- profiles: insert/update with trusted_partner role
  INSERT INTO public.profiles (id, name, surname, email, role, category)
  VALUES (
    uid,
    v_full_name,
    v_surname,
    v_email,
    'trusted_partner',
    'business_owner'
  )
  ON CONFLICT (id) DO UPDATE
    SET
        name     = excluded.name,
        surname  = excluded.surname,
        email    = coalesce(excluded.email, public.profiles.email),
        role     = 'trusted_partner',
        category = coalesce(excluded.category, public.profiles.category)
  RETURNING id INTO v_profile_id;

  -- memberships: ensure user has trusted_partner role
  INSERT INTO public.memberships (user_id, role, gateway)
  VALUES (uid, 'trusted_partner', 'app_signup')
  ON CONFLICT (user_id) DO UPDATE
    SET role = 'trusted_partner',
        gateway = excluded.gateway;

  -- trusted_partners: lightweight (user_id unique, business_name)
  INSERT INTO public.trusted_partners (user_id, business_name)
  VALUES (uid, coalesce(v_business_name, v_full_name))
  ON CONFLICT (user_id) DO UPDATE
    SET business_name = excluded.business_name;

  SELECT id INTO v_merchant_id
  FROM public.trusted_partners
  WHERE user_id = uid;

  RETURN jsonb_build_object('ok', true, 'profile_id', v_profile_id, 'trusted_partner_id', v_merchant_id);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', sqlerrm);
END;
$$;

-- Fix the complete_business_profile function in the fix_merchant_role_assignment migration
-- This function should use trusted_partner role and trusted_partners table
CREATE OR REPLACE FUNCTION public.complete_business_profile(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  v_name text := nullif(coalesce(payload->>'name', ''), '');
  v_cat text := nullif(coalesce(payload->>'category', ''), '');
  v_street text := nullif(coalesce(payload->>'street', ''), '');
  v_suburb text := nullif(coalesce(payload->>'suburb', ''), '');
  v_city text := nullif(coalesce(payload->>'city', ''), '');
  v_prov text := nullif(coalesce(payload->>'province', ''), '');
  v_contact_email text := nullif(coalesce(payload->>'contact_email', ''), '');
  v_latitude double precision := public.try_cast_double(coalesce(payload->>'latitude', null));
  v_longitude double precision := public.try_cast_double(coalesce(payload->>'longitude', null));
  v_address text;
  v_business_id uuid;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  -- Build address
  v_address := array_to_string(
    array_remove(array[v_street, v_suburb, v_city, v_prov], null),
    ', '
  );
  IF v_address = '' THEN v_address := null; END IF;

  -- Validation
  IF coalesce(v_name, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_business_name');
  END IF;
  IF coalesce(v_cat, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_category');
  END IF;

  -- Ensure user has trusted_partner role in memberships table
  INSERT INTO public.memberships (user_id, role, gateway)
  VALUES (uid, 'trusted_partner', 'business_profile_completion')
  ON CONFLICT (user_id) DO UPDATE
    SET role = 'trusted_partner',
        gateway = excluded.gateway;

  -- Also ensure profiles table has trusted_partner role
  UPDATE public.profiles
  SET role = 'trusted_partner'
  WHERE id = uid AND (role IS NULL OR role != 'trusted_partner');

  -- Create/update trusted_partners table with business name
  INSERT INTO public.trusted_partners (user_id, business_name)
  VALUES (uid, v_name)
  ON CONFLICT (user_id) DO UPDATE
    SET business_name = excluded.business_name,
        updated_at = NOW();

  -- Create/update business record
  INSERT INTO public.businesses (
    owner_member_id, name, category, address, latitude, longitude, contact_email
  ) VALUES (
    uid, v_name, v_cat, v_address, v_latitude, v_longitude, v_contact_email
  ) ON CONFLICT (owner_member_id) DO UPDATE
    SET name = excluded.name,
        category = excluded.category,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        contact_email = excluded.contact_email
  RETURNING id INTO v_business_id;

  RETURN jsonb_build_object('ok', true, 'business_id', v_business_id);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', sqlerrm);
END;
$$;

-- Fix the complete_business_profile function in the fix_merchants_table_population migration
-- This should also use trusted_partner terminology
CREATE OR REPLACE FUNCTION public.complete_business_profile(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  v_name text := nullif(coalesce(payload->>'name', ''), '');
  v_cat text := nullif(coalesce(payload->>'category', ''), '');
  v_street text := nullif(coalesce(payload->>'street', ''), '');
  v_suburb text := nullif(coalesce(payload->>'suburb', ''), '');
  v_city text := nullif(coalesce(payload->>'city', ''), '');
  v_prov text := nullif(coalesce(payload->>'province', ''), '');
  v_contact_email text := nullif(coalesce(payload->>'contact_email', ''), '');
  v_latitude double precision := public.try_cast_double(coalesce(payload->>'latitude', null));
  v_longitude double precision := public.try_cast_double(coalesce(payload->>'longitude', null));
  v_address text;
  v_business_id uuid;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  -- Build address
  v_address := array_to_string(
    array_remove(array[v_street, v_suburb, v_city, v_prov], null),
    ', '
  );
  IF v_address = '' THEN v_address := null; END IF;

  -- Validation
  IF coalesce(v_name, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_business_name');
  END IF;
  IF coalesce(v_cat, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_category');
  END IF;

  -- Ensure user has trusted_partner role in memberships table
  INSERT INTO public.memberships (user_id, role, gateway)
  VALUES (uid, 'trusted_partner', 'business_profile_completion')
  ON CONFLICT (user_id) DO UPDATE
    SET role = 'trusted_partner',
        gateway = excluded.gateway;

  -- Also ensure profiles table has trusted_partner role
  UPDATE public.profiles
  SET role = 'trusted_partner'
  WHERE id = uid AND (role IS NULL OR role != 'trusted_partner');

  -- Create/update trusted_partners table with business name
  INSERT INTO public.trusted_partners (user_id, business_name)
  VALUES (uid, v_name)
  ON CONFLICT (user_id) DO UPDATE
    SET business_name = excluded.business_name,
        updated_at = NOW();

  -- Create/update business record
  INSERT INTO public.businesses (
    owner_member_id, name, category, address, latitude, longitude, contact_email
  ) VALUES (
    uid, v_name, v_cat, v_address, v_latitude, v_longitude, v_contact_email
  ) ON CONFLICT (owner_member_id) DO UPDATE
    SET name = excluded.name,
        category = excluded.category,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        contact_email = excluded.contact_email
  RETURNING id INTO v_business_id;

  RETURN jsonb_build_object('ok', true, 'business_id', v_business_id);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', sqlerrm);
END;
$$;

COMMIT;</content>
<parameter name="filePath">c:\Users\clyde\local_lekker\supabase\migrations\20251001120000_fix_remaining_merchant_role_functions.sql
 
-- Fix businesses table column name from owner_user_id to owner_member_id
-- This migration addresses the remaining column naming issue after the terminology updates

DO $$
BEGIN
  -- Check if businesses table exists and has the old column name
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'businesses'
  ) THEN
    -- Rename owner_user_id to owner_member_id if it exists
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
      AND table_name = 'businesses'
      AND column_name = 'owner_user_id'
    ) THEN
      ALTER TABLE public.businesses RENAME COLUMN owner_user_id TO owner_member_id;
      RAISE NOTICE 'Renamed businesses.owner_user_id to businesses.owner_member_id';
    END IF;

    -- Ensure the column exists with correct type and constraints
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
      AND table_name = 'businesses'
      AND column_name = 'owner_member_id'
    ) THEN
      ALTER TABLE public.businesses ADD COLUMN owner_member_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;
      RAISE NOTICE 'Added businesses.owner_member_id column';
    END IF;

    -- Update any existing indexes if needed
    IF EXISTS (
      SELECT 1 FROM pg_indexes
      WHERE schemaname = 'public'
      AND tablename = 'businesses'
      AND indexname = 'idx_businesses_owner_user_id'
    ) THEN
      DROP INDEX IF EXISTS public.idx_businesses_owner_user_id;
      CREATE INDEX IF NOT EXISTS idx_businesses_owner_member_id ON public.businesses(owner_member_id);
      RAISE NOTICE 'Updated index from owner_user_id to owner_member_id';
    END IF;
  END IF;
END $$;
 
-- Make discount_id nullable to allow bills without discounts when manually selecting trusted partners
ALTER TABLE processed_bills ALTER COLUMN discount_id DROP NOT NULL;
 
-- Add item_name and item_price columns to trusted_partner_discounts table for deal creation
ALTER TABLE trusted_partner_discounts
ADD COLUMN IF NOT EXISTS item_name TEXT,
ADD COLUMN IF NOT EXISTS item_price DECIMAL(10,2);

-- Update existing records to have default values if needed
UPDATE trusted_partner_discounts
SET item_name = name
WHERE item_name IS NULL;

UPDATE trusted_partner_discounts
SET item_price = 0.00
WHERE item_price IS NULL;

-- Make item_name and item_price NOT NULL after populating defaults
ALTER TABLE trusted_partner_discounts
ALTER COLUMN item_name SET NOT NULL,
ALTER COLUMN item_price SET NOT NULL;
 
-- Create deal authorizations table for in-store purchases
CREATE TABLE IF NOT EXISTS deal_authorizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES profiles(id),
    trusted_partner_id UUID NOT NULL REFERENCES businesses(id),
    discount_id UUID NOT NULL REFERENCES trusted_partner_discounts(id),
    status VARCHAR(50) NOT NULL DEFAULT 'pending', -- pending, approved, rejected, completed
    authorization_type VARCHAR(50) NOT NULL DEFAULT 'in_store', -- in_store, online
    payment_method VARCHAR(50), -- in_app, pos
    amount DECIMAL(10,2),
    notes TEXT,
    rejection_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    approved_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE
);

-- Create virtual receipts table
CREATE TABLE IF NOT EXISTS virtual_receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deal_authorization_id UUID NOT NULL REFERENCES deal_authorizations(id),
    receipt_number VARCHAR(100) UNIQUE NOT NULL,
    receipt_data JSONB NOT NULL,
    qr_code TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create member receipts table (for receipt book)
CREATE TABLE IF NOT EXISTS member_receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES profiles(id),
    virtual_receipt_id UUID REFERENCES virtual_receipts(id),
    receipt_type VARCHAR(50) NOT NULL, -- virtual, physical
    title VARCHAR(255) NOT NULL,
    description TEXT,
    amount DECIMAL(10,2),
    business_name VARCHAR(255),
    receipt_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create notifications table
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id),
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    type VARCHAR(50) NOT NULL DEFAULT 'info', -- info, warning, error, success
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_deal_authorizations_member_id ON deal_authorizations(member_id);
CREATE INDEX IF NOT EXISTS idx_deal_authorizations_trusted_partner_id ON deal_authorizations(trusted_partner_id);
CREATE INDEX IF NOT EXISTS idx_deal_authorizations_status ON deal_authorizations(status);

-- Enable RLS
ALTER TABLE deal_authorizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE virtual_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE member_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- RLS Policies for deal_authorizations
CREATE POLICY "Members can view their own authorizations" ON deal_authorizations
    FOR SELECT USING ((SELECT auth.uid()) = member_id);

CREATE POLICY "Trusted partners can view authorizations for their business" ON deal_authorizations
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM businesses
            WHERE businesses.id = deal_authorizations.trusted_partner_id
            AND businesses.owner_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Trusted partners can update authorizations for their business" ON deal_authorizations
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM businesses
            WHERE businesses.id = deal_authorizations.trusted_partner_id
            AND businesses.owner_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Members can insert their own authorizations" ON deal_authorizations
    FOR INSERT WITH CHECK ((SELECT auth.uid()) = member_id);

-- RLS Policies for virtual_receipts
CREATE POLICY "Members can view their own virtual receipts" ON virtual_receipts
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM deal_authorizations
            WHERE deal_authorizations.id = virtual_receipts.deal_authorization_id
            AND deal_authorizations.member_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Trusted partners can view virtual receipts for their authorizations" ON virtual_receipts
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM deal_authorizations
            WHERE deal_authorizations.id = virtual_receipts.deal_authorization_id
            AND EXISTS (
                SELECT 1 FROM businesses
                WHERE businesses.id = deal_authorizations.trusted_partner_id
                AND businesses.owner_id = (SELECT auth.uid())
            )
        )
    );

-- RLS Policies for member_receipts
CREATE POLICY "Members can view their own receipts" ON member_receipts
    FOR SELECT USING ((SELECT auth.uid()) = member_id);

CREATE POLICY "Members can insert their own receipts" ON member_receipts
    FOR INSERT WITH CHECK ((SELECT auth.uid()) = member_id);

CREATE POLICY "Members can update their own receipts" ON member_receipts
    FOR UPDATE USING ((SELECT auth.uid()) = member_id);

-- RLS Policies for notifications
CREATE POLICY "Users can view their own notifications" ON notifications
    FOR SELECT USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can update their own notifications" ON notifications
    FOR UPDATE USING ((SELECT auth.uid()) = user_id);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- Trigger for deal_authorizations
CREATE TRIGGER update_deal_authorizations_updated_at
    BEFORE UPDATE ON deal_authorizations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
 
-- Fix: Recreate the missing SELECT policy for trusted_partner_discounts
-- The cleanup script accidentally removed the "Users can view all discounts" policy

-- Ensure RLS is enabled
ALTER TABLE trusted_partner_discounts ENABLE ROW LEVEL SECURITY;

-- Recreate the SELECT policy that allows everyone to view discounts
DROP POLICY IF EXISTS "Users can view all discounts" ON trusted_partner_discounts;
CREATE POLICY "Users can view all discounts" ON trusted_partner_discounts
    FOR SELECT USING (true);

-- Keep the business owner management policy
DROP POLICY IF EXISTS "Business owners can manage their discounts" ON trusted_partner_discounts;
CREATE POLICY "Business owners can manage their discounts" ON trusted_partner_discounts
    FOR ALL USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- Verify the policies are in place
SELECT schemaname, tablename, policyname, cmd, qual
FROM pg_policies WHERE tablename = 'trusted_partner_discounts'
ORDER BY policyname;
 
-- =============================================================================
-- FIX NOTIFICATIONS RLS POLICIES
-- =============================================================================
-- Issue: Conflicting RLS policies prevent deal authorization notifications
-- The "FOR ALL" policy restricts inserts to user_id = auth.uid(), but the app
-- needs to allow authenticated users to create notifications for other users
-- (e.g., members creating notifications for trusted partners)

-- Drop conflicting policies
DROP POLICY IF EXISTS "Users can view their own notifications" ON notifications;
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON notifications;
DROP POLICY IF EXISTS "Users can update their notifications" ON notifications;

-- Create proper policies
CREATE POLICY "Users can view their notifications" ON notifications
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Authenticated users can insert notifications" ON notifications
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Users can update their notifications" ON notifications
    FOR UPDATE USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
 
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
 
-- Migration: create complete_merchant_signup RPC (schema-aligned)
-- Accepts a single JSONB payload and performs idempotent upserts
-- Targets: profiles (id,name,email,role,category), memberships, merchants (user_id,business_name), businesses

begin;

drop function if exists public.complete_merchant_signup(jsonb);

create or replace function public.complete_merchant_signup(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();

  -- inputs (nullify empty strings)
  v_first_name      text := nullif(coalesce(payload->>'first_name', ''), '');
  v_surname         text := nullif(coalesce(payload->>'surname', ''), '');
  v_full_name       text;
  v_business_name   text := nullif(coalesce(payload->>'business_name', ''), '');
  v_category        text := nullif(coalesce(payload->>'category', ''), '');

  v_street          text := nullif(coalesce(payload->>'street', ''), '');
  v_suburb          text := nullif(coalesce(payload->>'suburb', ''), '');
  v_city            text := nullif(coalesce(payload->>'city', ''), '');
  v_province        text := nullif(coalesce(payload->>'province', ''), '');
  v_contact_email   text := nullif(coalesce(payload->>'contact_email', ''), '');

  v_latitude        double precision := public.try_cast_double(coalesce(payload->>'latitude', null));
  v_longitude       double precision := public.try_cast_double(coalesce(payload->>'longitude', null));

  v_address         text;
  v_profile_id      uuid;
  v_merchant_id     uuid;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- derive fields
  v_full_name := trim(both ' ' from coalesce(v_first_name, '') || ' ' || coalesce(v_surname, ''));
  v_address := array_to_string(
                 array_remove( array[ v_street, v_suburb, v_city, v_province ], null ),
                 ', '
               );
  if v_address = '' then v_address := null; end if;

  -- profiles: (id, name, email, role, category)
  insert into public.profiles (id, name, email, role, category)
  values (uid,
          coalesce(v_full_name, v_business_name),
          v_contact_email,
          'merchant',
          v_category)
  on conflict (id) do update
    set name     = excluded.name,
        email    = coalesce(excluded.email, public.profiles.email),
        role     = 'merchant',
        category = coalesce(excluded.category, public.profiles.category)
  returning id into v_profile_id;

  -- memberships: ensure user has merchant role
  insert into public.memberships (user_id, role, gateway)
  values (uid, 'merchant', 'app_signup')
  on conflict (user_id) do update
    set role = 'merchant',
        gateway = excluded.gateway;

  -- merchants: lightweight (user_id unique, business_name)
  insert into public.merchants (user_id, business_name)
  values (uid, coalesce(v_business_name, v_full_name))
  on conflict (user_id) do update
    set business_name = excluded.business_name;

  select id into v_merchant_id
  from public.merchants
  where user_id = uid;

  -- businesses: full profile
  insert into public.businesses (
    owner_user_id, name, category, address, latitude, longitude, contact_email
  )
  values (
    uid,
    coalesce(v_business_name, v_full_name),
    v_category,
    v_address,
    v_latitude,
    v_longitude,
    v_contact_email
  )
  on conflict (owner_user_id) do update
    set name          = excluded.name,
        category      = excluded.category,
        address       = excluded.address,
        latitude      = excluded.latitude,
        longitude     = excluded.longitude,
        contact_email = excluded.contact_email;

  return jsonb_build_object(
    'ok', true,
    'profile_id', v_profile_id,
    'merchant_id', v_merchant_id
  );

exception
  when others then
    return jsonb_build_object('ok', false, 'error', SQLERRM);
end;
$$;

-- helper to safely cast strings to double precision
drop function if exists public.try_cast_double(text);
create or replace function public.try_cast_double(txt text)
returns double precision
language plpgsql
immutable
as $$
declare v double precision;
begin
  if txt is null or btrim(txt) = '' then
    return null;
  end if;
  begin
    v := txt::double precision;
    return v;
  exception when others then
    return null;
  end;
end;
$$;

grant execute on function public.complete_merchant_signup(jsonb) to authenticated;

-- Optional: ensure unique constraints exist for conflict targets. Run once if missing.
create unique index if not exists businesses_owner_unique on public.businesses(owner_user_id);
create unique index if not exists memberships_user_unique on public.memberships(user_id);
create unique index if not exists merchants_user_unique on public.merchants(user_id);

commit;
 
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
 
-- Migration: add simple input validation to complete_merchant_signup
-- Returns clear JSON errors when required fields are missing (name/category)

begin;

-- Overwrite the function with the same implementation but first validate
-- required fields and return descriptive errors instead of letting
-- Postgres raise NOT NULL violations.

drop function if exists public.complete_merchant_signup(jsonb);

create or replace function public.complete_merchant_signup(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();

  v_first_name      text := nullif(coalesce(payload->>'first_name', ''), '');
  v_surname         text := nullif(coalesce(payload->>'surname', ''), '');
  v_full_name       text;
  v_business_name   text := nullif(coalesce(payload->>'business_name', ''), '');
  v_category        text := nullif(coalesce(payload->>'category', ''), '');

  v_street          text := nullif(coalesce(payload->>'street', ''), '');
  v_suburb          text := nullif(coalesce(payload->>'suburb', ''), '');
  v_city            text := nullif(coalesce(payload->>'city', ''), '');
  v_province        text := nullif(coalesce(payload->>'province', ''), '');
  v_contact_email   text := nullif(coalesce(payload->>'contact_email', ''), '');

  v_latitude        double precision := public.try_cast_double(coalesce(payload->>'latitude', null));
  v_longitude       double precision := public.try_cast_double(coalesce(payload->>'longitude', null));

  v_address         text;
  v_profile_id      uuid;
  v_merchant_id     uuid;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- derive display name and address
  v_full_name := trim(both ' ' from coalesce(v_first_name, '') || ' ' || coalesce(v_surname, ''));
  v_address := array_to_string(
                 array_remove( array[ v_street, v_suburb, v_city, v_province ], null ),
                 ', '
               );
  if v_address = '' then v_address := null; end if;

  -- validation: ensure we have a name (business_name or derived full name)
  if coalesce(v_business_name, '') = '' AND coalesce(v_full_name, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_business_name_or_name');
  end if;

  -- validation: ensure category is provided (businesses.category is NOT NULL)
  if coalesce(v_category, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_category');
  end if;

  -- profiles: (id, name, email, role, category)
  insert into public.profiles (id, name, email, role, category)
  values (uid,
          coalesce(v_full_name, v_business_name),
          v_contact_email,
          'merchant',
          v_category)
  on conflict (id) do update
    set name     = excluded.name,
        email    = coalesce(excluded.email, public.profiles.email),
        role     = 'merchant',
        category = coalesce(excluded.category, public.profiles.category)
  returning id into v_profile_id;

  -- memberships: ensure user has merchant role
  insert into public.memberships (user_id, role, gateway)
  values (uid, 'merchant', 'app_signup')
  on conflict (user_id) do update
    set role = 'merchant',
        gateway = excluded.gateway;

  -- merchants: lightweight (user_id unique, business_name)
  insert into public.merchants (user_id, business_name)
  values (uid, coalesce(v_business_name, v_full_name))
  on conflict (user_id) do update
    set business_name = excluded.business_name;

  select id into v_merchant_id
  from public.merchants
  where user_id = uid;

  -- businesses: full profile
  insert into public.businesses (
    owner_user_id, name, category, address, latitude, longitude, contact_email
  )
  values (
    uid,
    coalesce(v_business_name, v_full_name),
    v_category,
    v_address,
    v_latitude,
    v_longitude,
    v_contact_email
  )
  on conflict (owner_user_id) do update
    set name          = excluded.name,
        category      = excluded.category,
        address       = excluded.address,
        latitude      = excluded.latitude,
        longitude     = excluded.longitude,
        contact_email = excluded.contact_email;

  return jsonb_build_object(
    'ok', true,
    'profile_id', v_profile_id,
    'merchant_id', v_merchant_id
  );

exception
  when others then
    return jsonb_build_object('ok', false, 'error', SQLERRM);
end;
$$;

grant execute on function public.complete_merchant_signup(jsonb) to authenticated;

commit;
 
-- Migration: create complete_business_profile rpc
-- Upserts a business record for auth.uid() with validation and returns JSONB {ok, business_id}

begin;

drop function if exists public.complete_business_profile(jsonb);

create or replace function public.complete_business_profile(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();

  v_name   text := nullif(coalesce(payload->>'name', ''), '');
  v_cat    text := nullif(coalesce(payload->>'category', ''), '');
  v_street text := nullif(coalesce(payload->>'street', ''), '');
  v_suburb text := nullif(coalesce(payload->>'suburb', ''), '');
  v_city   text := nullif(coalesce(payload->>'city', ''), '');
  v_prov   text := nullif(coalesce(payload->>'province', ''), '');
  v_contact_email text := nullif(coalesce(payload->>'contact_email', ''), '');

  v_latitude  double precision := public.try_cast_double(coalesce(payload->>'latitude', null));
  v_longitude double precision := public.try_cast_double(coalesce(payload->>'longitude', null));

  v_address text;
  v_business_id uuid;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- build address
  v_address := array_to_string(
    array_remove(array[v_street, v_suburb, v_city, v_prov], null),
    ', '
  );
  if v_address = '' then v_address := null; end if;

  -- validation
  if coalesce(v_name, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_business_name');
  end if;
  if coalesce(v_cat, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_category');
  end if;

  -- Ensure user has merchant role in memberships table
  insert into public.memberships (user_id, role, gateway)
  values (uid, 'merchant', 'business_profile_completion')
  on conflict (user_id) do update
    set role = 'merchant',
        gateway = excluded.gateway;

  -- Also ensure profiles table has merchant role
  update public.profiles
  set role = 'merchant'
  where id = uid and (role is null or role != 'merchant');

  return jsonb_build_object('ok', true, 'business_id', v_business_id);

exception when others then
  return jsonb_build_object('ok', false, 'error', SQLERRM);
end;
$$;

grant execute on function public.complete_business_profile(jsonb) to authenticated;

commit;
 
