-- Update complete_business_profile function to include social media handles
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
  v_address text := nullif(coalesce(payload->>'address', ''), '');
  v_contact_email text := nullif(coalesce(payload->>'contact_email', ''), '');
  v_contact_number text := nullif(coalesce(payload->>'contact_number', ''), '');
  v_latitude double precision := public.try_cast_double(coalesce(payload->>'latitude', null));
  v_longitude double precision := public.try_cast_double(coalesce(payload->>'longitude', null));
  v_logo_url text := nullif(coalesce(payload->>'logo_url', ''), '');
  -- Social media handles
  v_facebook_handle text := nullif(coalesce(payload->>'facebook_handle', ''), '');
  v_instagram_handle text := nullif(coalesce(payload->>'instagram_handle', ''), '');
  v_website_url text := nullif(coalesce(payload->>'website_url', ''), '');
  v_business_email text := nullif(coalesce(payload->>'business_email', ''), '');
  v_business_id uuid;
  v_profile_address text;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  -- If address not provided in payload, get it from profiles table
  IF v_address IS NULL OR v_address = '' THEN
    SELECT array_to_string(
      array_remove(array[street, suburb, city, province], null),
      ', '
    ) INTO v_profile_address
    FROM public.profiles
    WHERE id = uid;

    v_address := nullif(v_profile_address, '');
  END IF;

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
  SET role = 'trusted_partner',
      category = v_cat
  WHERE id = uid AND (role IS NULL OR role != 'trusted_partner');

  -- Create/update trusted_partners table with business name
  INSERT INTO public.trusted_partners (user_id, business_name)
  VALUES (uid, v_name)
  ON CONFLICT (user_id) DO UPDATE
    SET business_name = excluded.business_name,
        updated_at = now();

  -- Create/update business record (including social media handles)
  INSERT INTO public.businesses (
    owner_member_id, name, category, address, latitude, longitude, 
    contact_email, contact_number, logo_url,
    facebook_handle, instagram_handle, website_url, business_email,
    verified
  ) VALUES (
    uid, v_name, v_cat, v_address, v_latitude, v_longitude, 
    v_contact_email, v_contact_number, v_logo_url,
    v_facebook_handle, v_instagram_handle, v_website_url, v_business_email,
    true
  ) ON CONFLICT (owner_member_id) DO UPDATE
    SET name = excluded.name,
        category = excluded.category,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        contact_email = excluded.contact_email,
        contact_number = excluded.contact_number,
        logo_url = excluded.logo_url,
        facebook_handle = excluded.facebook_handle,
        instagram_handle = excluded.instagram_handle,
        website_url = excluded.website_url,
        business_email = excluded.business_email,
        verified = true
  RETURNING id INTO v_business_id;

  RETURN jsonb_build_object('ok', true, 'business_id', v_business_id);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', sqlerrm);
END;
$$;
