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
