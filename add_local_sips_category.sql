-- =====================================================
-- ADD LOCAL SIPS (LOCALLY PRODUCED ALCOHOL) CATEGORY
-- =====================================================
-- Mirrors the "Fresh & Local" category:
--   1. Trusted partner opt-in flag + description on businesses.
--   2. Admin-managed liquor licence documents + verified flag.
--   3. Member 18+ age confirmation stored once per account.
--   4. Interest form flag + admin_update_trusted_partner RPC support.

BEGIN;

-- ---------------------------------------------------------------
-- 1. Businesses opt-in + licence verification state
-- ---------------------------------------------------------------
ALTER TABLE public.businesses
ADD COLUMN IF NOT EXISTS sells_alcohol BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.businesses.sells_alcohol IS
  'True when the partner has opted into the Local Sips locally produced alcohol category';

ALTER TABLE public.businesses
ADD COLUMN IF NOT EXISTS alcohol_description TEXT;

COMMENT ON COLUMN public.businesses.alcohol_description IS
  'Brief description of the locally produced wines/alcohol this partner sells';

ALTER TABLE public.businesses
ADD COLUMN IF NOT EXISTS liquor_license_verified BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.businesses.liquor_license_verified IS
  'Set by an admin once the partner liquor/distribution licence documents have been checked';

ALTER TABLE public.businesses
ADD COLUMN IF NOT EXISTS liquor_license_verified_at TIMESTAMPTZ;

ALTER TABLE public.businesses
ADD COLUMN IF NOT EXISTS liquor_license_verified_by UUID;

CREATE INDEX IF NOT EXISTS idx_businesses_sells_alcohol
  ON public.businesses(sells_alcohol)
  WHERE sells_alcohol = true;

-- ---------------------------------------------------------------
-- 2. Liquor licence documents (admin managed)
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.partner_liquor_licenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trusted_partner_id UUID NOT NULL,
  file_path TEXT NOT NULL,
  file_name TEXT NOT NULL,
  mime_type TEXT,
  doc_type TEXT NOT NULL DEFAULT 'other',
  uploaded_by UUID,
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.partner_liquor_licenses IS
  'National liquor / distribution licence documents for Local Sips partners. Admin managed.';
COMMENT ON COLUMN public.partner_liquor_licenses.trusted_partner_id IS
  'auth user id of the partner (businesses.owner_member_id)';
COMMENT ON COLUMN public.partner_liquor_licenses.file_path IS
  'Object path inside the private partner-liquor-licenses storage bucket';

CREATE INDEX IF NOT EXISTS idx_partner_liquor_licenses_partner
  ON public.partner_liquor_licenses(trusted_partner_id);

ALTER TABLE public.partner_liquor_licenses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage liquor licences" ON public.partner_liquor_licenses;
CREATE POLICY "Admins manage liquor licences"
  ON public.partner_liquor_licenses
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = auth.uid() AND m.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = auth.uid() AND m.role = 'admin'
    )
  );

-- Partner may see that documents exist for their own business, but cannot add/remove them.
DROP POLICY IF EXISTS "Partners read own liquor licences" ON public.partner_liquor_licenses;
CREATE POLICY "Partners read own liquor licences"
  ON public.partner_liquor_licenses
  FOR SELECT
  TO authenticated
  USING (trusted_partner_id = auth.uid());

-- ---------------------------------------------------------------
-- 3. Private storage bucket for the licence documents
-- ---------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('partner-liquor-licenses', 'partner-liquor-licenses', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Admins read liquor licence files" ON storage.objects;
CREATE POLICY "Admins read liquor licence files"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'partner-liquor-licenses'
    AND EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = auth.uid() AND m.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Admins upload liquor licence files" ON storage.objects;
CREATE POLICY "Admins upload liquor licence files"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'partner-liquor-licenses'
    AND EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = auth.uid() AND m.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Admins delete liquor licence files" ON storage.objects;
CREATE POLICY "Admins delete liquor licence files"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'partner-liquor-licenses'
    AND EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = auth.uid() AND m.role = 'admin'
    )
  );

-- ---------------------------------------------------------------
-- 4. Member 18+ confirmation (once per account)
-- ---------------------------------------------------------------
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS age_verified_18 BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS age_verified_at TIMESTAMPTZ;

COMMENT ON COLUMN public.profiles.age_verified_18 IS
  'True once the member has self-confirmed they are 18 or older (Local Sips gate)';

CREATE OR REPLACE FUNCTION public.confirm_member_age_18(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot confirm age for another user';
  END IF;

  UPDATE public.profiles
  SET age_verified_18 = TRUE,
      age_verified_at = NOW(),
      updated_at = NOW()
  WHERE id = p_user_id;

  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.confirm_member_age_18(UUID) TO authenticated;

-- ---------------------------------------------------------------
-- 5. Interest form flag
-- ---------------------------------------------------------------
ALTER TABLE public.tp_inquiries
ADD COLUMN IF NOT EXISTS sells_alcohol BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.tp_inquiries.sells_alcohol IS
  'True when the prospective partner indicated they sell locally produced alcohol';

-- ---------------------------------------------------------------
-- 6. Extend the admin update RPC with the Local Sips fields
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
  'Local Sips columns' as verification,
  table_name,
  column_name,
  data_type,
  column_default
FROM information_schema.columns
WHERE (table_name = 'businesses'
       AND column_name IN ('sells_alcohol', 'alcohol_description', 'liquor_license_verified'))
   OR (table_name = 'profiles'
       AND column_name IN ('age_verified_18', 'age_verified_at'))
   OR (table_name = 'tp_inquiries' AND column_name = 'sells_alcohol')
ORDER BY table_name, column_name;

SELECT 'Licence table' as verification, table_name
FROM information_schema.tables
WHERE table_name = 'partner_liquor_licenses';

SELECT 'Alcohol index' as verification, indexname, tablename
FROM pg_indexes
WHERE indexname = 'idx_businesses_sells_alcohol';

SELECT 'Licence bucket' as verification, id, public
FROM storage.buckets
WHERE id = 'partner-liquor-licenses';
