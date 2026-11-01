-- Migration: create complete_trusted_partner_signup RPC (schema-aligned)
-- Accepts a single JSONB payload and performs idempotent upserts
-- Targets: profiles (id,name,email,role,category), memberships, trusted_partners (user_id,business_name), businesses

begin;

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

  -- profiles: (id, name, email, role, category)
  insert into public.profiles (id, name, email, role, category)
  values (uid,
          coalesce(v_full_name, v_business_name),
          v_contact_email,
          'trusted_partner',
          v_category)
  on conflict (id) do update
    set name     = excluded.name,
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

  return jsonb_build_object(
    'ok', true,
    'profile_id', v_profile_id,
    'partner_id', v_partner_id
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

grant execute on function public.complete_trusted_partner_signup(jsonb) to authenticated;

-- Optional: ensure unique constraints exist for conflict targets. Run once if missing.
create unique index if not exists businesses_owner_unique on public.businesses(owner_user_id);
create unique index if not exists memberships_user_unique on public.memberships(user_id);
create unique index if not exists trusted_partners_user_unique on public.trusted_partners(user_id);

commit;
