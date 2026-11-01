-- Migration: Fix recursive RLS policies on public.users and create safe owner-only policies
-- Purpose: If a POLICY on public.users causes infinite recursion (42P17), this migration
-- will remove existing policies on public.users and replace them with narrow, safe
-- policies that rely only on auth.uid(). It also backfills missing public.users rows
-- for identities referenced by application tables (businesses/merchants/memberships).
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
  exception when undefined_table then
    raise notice 'One or more referencing tables (businesses/merchants/memberships) do not exist; skipping backfill';
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
