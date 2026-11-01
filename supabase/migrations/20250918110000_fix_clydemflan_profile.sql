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