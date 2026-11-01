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