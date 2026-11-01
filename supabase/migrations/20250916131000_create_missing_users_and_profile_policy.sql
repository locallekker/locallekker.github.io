-- Migration: Create missing public.users rows (if table exists), ensure minimal profiles,
-- and add a safe RLS policy allowing authenticated users to insert/update their own profile.
-- Idempotent: uses conditional checks and ON CONFLICT DO NOTHING

begin;

-- Only run the users population if the table public.users exists
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'users') then
    -- Insert minimal public.users rows for any user ids referenced by businesses/merchants/memberships
    -- Populate the required NOT NULL/UNIQUE `email` column using auth.users.email when available,
    -- otherwise use a unique placeholder based on the uid to avoid uniqueness collisions.
    insert into public.users (id, email, created_at)
    select distinct t.uid,
           coalesce(au.email, ('no-email+' || t.uid::text || '@example.invalid')),
           now()
    from (
      select owner_member_id as uid from public.businesses
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
  select owner_member_id as uid from public.businesses
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
