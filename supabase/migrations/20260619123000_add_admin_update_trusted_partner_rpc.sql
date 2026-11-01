BEGIN;

CREATE OR REPLACE FUNCTION public.admin_update_trusted_partner(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
  v_target_user_id uuid := NULLIF(payload->>'partner_id', '')::uuid;
  v_business_id uuid;
  v_name text := NULLIF(trim(coalesce(payload->>'name', '')), '');
  v_surname text := NULLIF(trim(coalesce(payload->>'surname', '')), '');
  v_email text := NULLIF(lower(trim(coalesce(payload->>'email', ''))), '');
  v_contact text := trim(coalesce(payload->>'contact', ''));
  v_city text := trim(coalesce(payload->>'city', ''));
  v_business_name text := NULLIF(trim(coalesce(payload->>'business_name', '')), '');
  v_category text := NULLIF(trim(coalesce(payload->>'category', '')), '');
  v_address text := trim(coalesce(payload->>'address', ''));
  v_contact_number text := trim(coalesce(payload->>'contact_number', ''));
  v_contact_email text := NULLIF(lower(trim(coalesce(payload->>'contact_email', ''))), '');
  v_facebook_handle text := trim(coalesce(payload->>'facebook_handle', ''));
  v_instagram_handle text := trim(coalesce(payload->>'instagram_handle', ''));
  v_website_url text := trim(coalesce(payload->>'website_url', ''));
  v_logo_url text := NULLIF(trim(coalesce(payload->>'logo_url', '')), '');
BEGIN
  IF v_admin_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.memberships
    WHERE user_id = v_admin_id
      AND role = 'admin'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'admin_access_required');
  END IF;

  IF v_target_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_partner_id');
  END IF;

  IF v_email IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_email');
  END IF;

  IF v_business_name IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_business_name');
  END IF;

  IF v_category IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_category');
  END IF;

  UPDATE public.profiles
  SET name = COALESCE(v_name, name),
      surname = COALESCE(v_surname, surname),
      email = v_email,
      contact = v_contact,
      city = v_city,
      updated_at = NOW()
  WHERE id = v_target_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'partner_profile_not_found');
  END IF;

  INSERT INTO public.businesses (
    owner_member_id,
    name,
    category,
    city,
    address,
    contact_number,
    contact_email,
    facebook_handle,
    instagram_handle,
    website_url,
    logo_url,
    updated_at,
    created_at
  )
  VALUES (
    v_target_user_id,
    v_business_name,
    v_category,
    v_city,
    NULLIF(v_address, ''),
    NULLIF(v_contact_number, ''),
    COALESCE(v_contact_email, v_email),
    NULLIF(v_facebook_handle, ''),
    NULLIF(v_instagram_handle, ''),
    NULLIF(v_website_url, ''),
    v_logo_url,
    NOW(),
    NOW()
  )
  ON CONFLICT (owner_member_id) DO UPDATE
    SET name = EXCLUDED.name,
        category = EXCLUDED.category,
        city = EXCLUDED.city,
        address = EXCLUDED.address,
        contact_number = EXCLUDED.contact_number,
        contact_email = EXCLUDED.contact_email,
        facebook_handle = EXCLUDED.facebook_handle,
        instagram_handle = EXCLUDED.instagram_handle,
        website_url = EXCLUDED.website_url,
        logo_url = COALESCE(EXCLUDED.logo_url, public.businesses.logo_url),
        updated_at = NOW()
  RETURNING id INTO v_business_id;

  BEGIN
    UPDATE public.trusted_partners
    SET business_name = v_business_name,
        updated_at = NOW()
    WHERE user_id = v_target_user_id;
  EXCEPTION WHEN undefined_column THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'partner_id', v_target_user_id,
    'business_id', v_business_id,
    'logo_url', COALESCE(v_logo_url, '')
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_trusted_partner(jsonb) TO authenticated;

COMMIT;