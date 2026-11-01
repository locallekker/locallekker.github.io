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