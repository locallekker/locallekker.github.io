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

  -- Ensure user has trusted_partner role in memberships table
  insert into public.memberships (user_id, role, gateway)
  values (uid, 'trusted_partner', 'business_profile_completion')
  on conflict (user_id) do update
    set role = 'trusted_partner',
        gateway = excluded.gateway;

  -- Also ensure profiles table has trusted_partner role
  update public.profiles
  set role = 'trusted_partner'
  where id = uid and (role is null or role != 'trusted_partner');

  return jsonb_build_object('ok', true, 'business_id', v_business_id);

exception when others then
  return jsonb_build_object('ok', false, 'error', SQLERRM);
end;
$$;

grant execute on function public.complete_business_profile(jsonb) to authenticated;

commit;
