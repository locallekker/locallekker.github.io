-- =====================================================
-- ADD LOCALLY ACTIVE (SPORT / FITNESS) CATEGORY
-- =====================================================
-- Mirrors the "Fresh & Local" category (simple opt-in flag + description,
-- no age gate or licence verification needed for sport/fitness partners):
--   1. Trusted partner opt-in flag + description on businesses.
--   2. Interest form flag + admin_update_trusted_partner RPC support.

BEGIN;

-- ---------------------------------------------------------------
-- 1. Businesses opt-in
-- ---------------------------------------------------------------
ALTER TABLE public.businesses
ADD COLUMN IF NOT EXISTS offers_sports_activities BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.businesses.offers_sports_activities IS
  'True when the partner has opted into the Locally Active sport/fitness category';

ALTER TABLE public.businesses
ADD COLUMN IF NOT EXISTS sports_description TEXT;

COMMENT ON COLUMN public.businesses.sports_description IS
  'Brief description of the sport/fitness activities this partner offers';

CREATE INDEX IF NOT EXISTS idx_businesses_offers_sports_activities
  ON public.businesses(offers_sports_activities)
  WHERE offers_sports_activities = true;

-- ---------------------------------------------------------------
-- 2. Interest form flag
-- ---------------------------------------------------------------
ALTER TABLE public.tp_inquiries
ADD COLUMN IF NOT EXISTS offers_sports_activities BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.tp_inquiries.offers_sports_activities IS
  'True when the prospective partner indicated they offer sport/fitness activities';

-- ---------------------------------------------------------------
-- 3. Extend the admin update RPC with the Locally Active fields
-- ---------------------------------------------------------------
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
  v_sells_fresh_produce boolean := coalesce((payload->>'sells_fresh_produce')::boolean, false);
  v_produce_description text := NULLIF(trim(coalesce(payload->>'produce_description', '')), '');
  v_sells_alcohol boolean := coalesce((payload->>'sells_alcohol')::boolean, false);
  v_alcohol_description text := NULLIF(trim(coalesce(payload->>'alcohol_description', '')), '');
  v_liquor_license_verified boolean := coalesce((payload->>'liquor_license_verified')::boolean, false);
  v_offers_sports_activities boolean := coalesce((payload->>'offers_sports_activities')::boolean, false);
  v_sports_description text := NULLIF(trim(coalesce(payload->>'sports_description', '')), '');
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
    sells_fresh_produce,
    produce_description,
    sells_alcohol,
    alcohol_description,
    liquor_license_verified,
    liquor_license_verified_at,
    liquor_license_verified_by,
    offers_sports_activities,
    sports_description,
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
    v_sells_fresh_produce,
    v_produce_description,
    v_sells_alcohol,
    v_alcohol_description,
    v_liquor_license_verified,
    CASE WHEN v_liquor_license_verified THEN NOW() END,
    CASE WHEN v_liquor_license_verified THEN v_admin_id END,
    v_offers_sports_activities,
    v_sports_description,
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
        sells_fresh_produce = EXCLUDED.sells_fresh_produce,
        produce_description = EXCLUDED.produce_description,
        sells_alcohol = EXCLUDED.sells_alcohol,
        alcohol_description = EXCLUDED.alcohol_description,
        liquor_license_verified = EXCLUDED.liquor_license_verified,
        -- keep the original verification timestamp when the flag was already set
        liquor_license_verified_at = CASE
          WHEN EXCLUDED.liquor_license_verified AND NOT public.businesses.liquor_license_verified
            THEN NOW()
          WHEN EXCLUDED.liquor_license_verified THEN public.businesses.liquor_license_verified_at
          ELSE NULL
        END,
        liquor_license_verified_by = CASE
          WHEN EXCLUDED.liquor_license_verified AND NOT public.businesses.liquor_license_verified
            THEN v_admin_id
          WHEN EXCLUDED.liquor_license_verified THEN public.businesses.liquor_license_verified_by
          ELSE NULL
        END,
        offers_sports_activities = EXCLUDED.offers_sports_activities,
        sports_description = EXCLUDED.sports_description,
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

-- =====================================================
-- VERIFICATION
-- =====================================================
SELECT
  'Locally Active columns' as verification,
  table_name,
  column_name,
  data_type,
  column_default
FROM information_schema.columns
WHERE (table_name = 'businesses'
       AND column_name IN ('offers_sports_activities', 'sports_description'))
   OR (table_name = 'tp_inquiries' AND column_name = 'offers_sports_activities')
ORDER BY table_name, column_name;

SELECT 'Sports index' as verification, indexname, tablename
FROM pg_indexes
WHERE indexname = 'idx_businesses_offers_sports_activities';
