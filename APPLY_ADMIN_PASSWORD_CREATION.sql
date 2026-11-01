-- =====================================================
-- COMPLETE SQL FOR ADMIN PASSWORD-BASED TRUSTED PARTNER CREATION
-- Apply this entire script in Supabase SQL Editor
-- Date: December 2, 2025
-- =====================================================

-- =====================================================
-- STEP 1: Create RPC function for admin to create trusted partners with password
-- =====================================================

CREATE OR REPLACE FUNCTION public.admin_create_trusted_partner(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  p_email text := lower(coalesce(payload->>'email',''));
  p_password text := coalesce(payload->>'password','');
  p_metadata jsonb := coalesce(payload->'metadata', '{}'::jsonb);
  v_user_id uuid;
  v_existing_user uuid;
BEGIN
  IF p_email = '' OR p_password = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_email_or_password');
  END IF;

  -- Merge required flags into metadata to drive app/trigger behavior
  p_metadata := p_metadata
    || jsonb_build_object('user_type','trusted_partner')
    || jsonb_build_object('admin_created','true')
    || jsonb_build_object('password_set','true')
    || jsonb_build_object('email_verified','true');

  -- If auth user exists for email, reuse and refresh; else attempt creation
  SELECT id INTO v_existing_user FROM auth.users WHERE lower(email) = p_email LIMIT 1;

  IF v_existing_user IS NOT NULL THEN
    v_user_id := v_existing_user;
    -- Reactivate and refresh metadata/timestamps
    UPDATE auth.users
    SET banned_until = NULL,
        deleted_at = NULL,
        email_confirmed_at = NOW(),
        raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || p_metadata,
        updated_at = NOW(),
        created_at = NOW()
    WHERE id = v_user_id;
  ELSE
    -- Create auth user with password. Prefer auth.sign_up (Supabase v2) with fallbacks to legacy create_user.
    BEGIN
      -- Preferred: auth.sign_up with named args
      SELECT (auth.sign_up(email => p_email, password => p_password, data => p_metadata)).user_id
      INTO v_user_id;
    EXCEPTION
      WHEN undefined_function THEN
        BEGIN
          -- auth.sign_up positional args
          SELECT (auth.sign_up(p_email, p_password, p_metadata)).user_id
          INTO v_user_id;
        EXCEPTION WHEN undefined_function THEN
          BEGIN
            -- Legacy: auth.create_user with named args
            SELECT (auth.create_user(
                      email => p_email,
                      password => p_password,
                      email_confirm => true,
                      user_metadata => p_metadata
                    )).id
            INTO v_user_id;
          EXCEPTION WHEN undefined_function THEN
            BEGIN
              -- Legacy positional signature
              SELECT (auth.create_user(p_email, p_password, TRUE, p_metadata)).id
              INTO v_user_id;
            EXCEPTION WHEN OTHERS THEN
              RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
            END;
          END;
        END;
      WHEN OTHERS THEN
        RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
    END;
  END IF;

  -- Mark email as confirmed (defensive in case create_user didn't set it)
  UPDATE auth.users SET email_confirmed_at = now()
  WHERE id = v_user_id;

  -- Create business record immediately with admin deal permission enabled
  -- This allows admins to create deals right away without waiting for profile completion
  BEGIN
    INSERT INTO public.businesses (
      owner_member_id,
      name,
      category,
      verified,
      allow_admin_deal_creation,
      created_at,
      updated_at
    ) VALUES (
      v_user_id,
      COALESCE(p_metadata->>'business_name', 'Pending Setup'),
      'General', -- Default category, can be updated during profile completion
      true, -- Business is verified immediately for admin-created partners
      true, -- Enable admin deal creation immediately
      NOW(),
      NOW()
    );
  EXCEPTION WHEN OTHERS THEN
    -- Non-fatal: business record creation can fail if already exists
    -- This is okay - the complete_business_profile will handle it later
    RAISE WARNING 'Business record creation skipped for user %: %', v_user_id, SQLERRM;
  END;

  -- Ensure profile, membership, and trusted_partner records exist (trigger may not fire on updates)
  BEGIN
    -- Upsert profile with admin-created trusted partner flags
    INSERT INTO public.profiles (
      id, email, role, name, surname,
      admin_created, password_set, verified, email_verified,
      created_at, updated_at
    ) VALUES (
      v_user_id,
      p_email,
      'trusted_partner',
      COALESCE(p_metadata->>'name', ''),
      COALESCE(p_metadata->>'surname', ''),
      true,
      true,
      true,
      true,
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
      email = EXCLUDED.email,
      role = 'trusted_partner',
      name = COALESCE(EXCLUDED.name, public.profiles.name),
      surname = COALESCE(EXCLUDED.surname, public.profiles.surname),
      admin_created = true,
      password_set = true,
      verified = true,
      email_verified = true,
      updated_at = NOW();

    -- Upsert membership as trusted_partner
    INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
    VALUES (v_user_id, 'trusted_partner', 'admin_creation', NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE SET
      role = 'trusted_partner',
      gateway = 'admin_creation',
      updated_at = NOW();

    -- Ensure trusted_partners record exists with business_name
    INSERT INTO public.trusted_partners (user_id, business_name, created_at, updated_at)
    VALUES (v_user_id, COALESCE(p_metadata->>'business_name', ''), NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE SET
      business_name = EXCLUDED.business_name,
      updated_at = NOW();
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to create user profile';
  END;

  RETURN jsonb_build_object('ok', true, 'user_id', v_user_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_create_trusted_partner(jsonb) TO authenticated;

-- =====================================================
-- STEP 2: Update trigger to auto-verify admin-created users
-- =====================================================

CREATE OR REPLACE FUNCTION public.handle_new_user_role_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_type text;
  user_role text;
  user_email text;
  user_name text;
  user_surname text;
  business_name text;
  admin_created_val boolean := false;
  password_set_val boolean := true;
  verified_val boolean := null;
  email_verified_val boolean := null;
BEGIN
  -- Get user_type from either app or user metadata
  user_type := COALESCE(
    NEW.raw_app_meta_data->>'user_type',
    NEW.raw_user_meta_data->>'user_type'
  );

  -- Default to 'user' if no type specified
  IF user_type IS NULL THEN
    user_type := 'user';
  END IF;

  user_email := COALESCE(NEW.email, NEW.raw_user_meta_data->>'email', NEW.raw_app_meta_data->>'email', '');

  user_name := COALESCE(
    NEW.raw_app_meta_data->>'name',
    NEW.raw_user_meta_data->>'name'
  );
  user_surname := COALESCE(
    NEW.raw_app_meta_data->>'surname',
    NEW.raw_user_meta_data->>'surname'
  );
  business_name := COALESCE(
    NEW.raw_app_meta_data->>'business_name',
    NEW.raw_user_meta_data->>'business_name'
  );

  -- Determine role based on user_type
  IF user_type = 'merchant' THEN
    user_role := 'merchant';
  ELSIF user_type = 'trusted_partner' THEN
    user_role := 'trusted_partner';
  ELSE
    user_role := 'user';
  END IF;

  -- Parse boolean values from metadata (handle both string and boolean formats)
  BEGIN
    -- admin_created
    IF NEW.raw_app_meta_data->>'admin_created' = 'true' OR NEW.raw_user_meta_data->>'admin_created' = 'true' THEN
      admin_created_val := true;
    ELSIF NEW.raw_app_meta_data->>'admin_created' = 'false' OR NEW.raw_user_meta_data->>'admin_created' = 'false' THEN
      admin_created_val := false;
    END IF;

    -- password_set
    IF NEW.raw_app_meta_data->>'password_set' = 'true' OR NEW.raw_user_meta_data->>'password_set' = 'true' THEN
      password_set_val := true;
    ELSIF NEW.raw_app_meta_data->>'password_set' = 'false' OR NEW.raw_user_meta_data->>'password_set' = 'false' THEN
      password_set_val := false;
    END IF;

    -- verified (prefer metadata; default to admin_created=true)
    IF NEW.raw_app_meta_data->>'verified' = 'true' OR NEW.raw_user_meta_data->>'verified' = 'true' THEN
      verified_val := true;
    ELSIF NEW.raw_app_meta_data->>'verified' = 'false' OR NEW.raw_user_meta_data->>'verified' = 'false' THEN
      verified_val := false;
    ELSE
      verified_val := NULL; -- derive later
    END IF;

    -- email_verified (prefer metadata; default to admin_created=true)
    IF NEW.raw_app_meta_data->>'email_verified' = 'true' OR NEW.raw_user_meta_data->>'email_verified' = 'true' THEN
      email_verified_val := true;
    ELSIF NEW.raw_app_meta_data->>'email_verified' = 'false' OR NEW.raw_user_meta_data->>'email_verified' = 'false' THEN
      email_verified_val := false;
    ELSE
      email_verified_val := NULL; -- derive later
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Failed to parse boolean metadata for user %: %', NEW.id, SQLERRM;
  END;

  RAISE WARNING 'Trigger Debug - user_type: %, role: %, admin_created: %, password_set: %', user_type, user_role, admin_created_val, password_set_val;

  -- Create profile record
  BEGIN
    INSERT INTO public.profiles (
      id,
      email,
      role,
      name,
      surname,
      street,
      suburb,
      city,
      province,
      contact,
      gender,
      ethnicity,
      date_of_birth,
      admin_created,
      password_set,
      verified,
      email_verified,
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      user_email,
      COALESCE(user_role, 'user'),
      COALESCE(user_name, ''),
      COALESCE(user_surname, ''),
      COALESCE(NEW.raw_app_meta_data->>'street', NEW.raw_user_meta_data->>'street'),
      COALESCE(NEW.raw_app_meta_data->>'suburb', NEW.raw_user_meta_data->>'suburb'),
      COALESCE(NEW.raw_app_meta_data->>'city', NEW.raw_user_meta_data->>'city'),
      COALESCE(NEW.raw_app_meta_data->>'province', NEW.raw_user_meta_data->>'province'),
      COALESCE(NEW.raw_app_meta_data->>'contact', NEW.raw_user_meta_data->>'contact'),
      COALESCE(NEW.raw_app_meta_data->>'gender', NEW.raw_user_meta_data->>'gender'),
      COALESCE(NEW.raw_app_meta_data->>'ethnicity', NEW.raw_user_meta_data->>'ethnicity'),
      CASE
        WHEN COALESCE(NEW.raw_app_meta_data->>'date_of_birth', NEW.raw_user_meta_data->>'date_of_birth') IS NOT NULL
        THEN (COALESCE(NEW.raw_app_meta_data->>'date_of_birth', NEW.raw_user_meta_data->>'date_of_birth'))::timestamp with time zone
        ELSE NULL
      END,
      admin_created_val,
      password_set_val,
      COALESCE(verified_val, CASE WHEN admin_created_val THEN true ELSE NULL END),
      COALESCE(email_verified_val, CASE WHEN admin_created_val THEN true ELSE NULL END),
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO UPDATE
      SET email = COALESCE(EXCLUDED.email, public.profiles.email),
          role = COALESCE(EXCLUDED.role, public.profiles.role),
          name = COALESCE(EXCLUDED.name, public.profiles.name),
          surname = COALESCE(EXCLUDED.surname, public.profiles.surname),
          street = COALESCE(EXCLUDED.street, public.profiles.street),
          suburb = COALESCE(EXCLUDED.suburb, public.profiles.suburb),
          city = COALESCE(EXCLUDED.city, public.profiles.city),
          province = COALESCE(EXCLUDED.province, public.profiles.province),
          contact = COALESCE(EXCLUDED.contact, public.profiles.contact),
          gender = COALESCE(EXCLUDED.gender, public.profiles.gender),
          ethnicity = COALESCE(EXCLUDED.ethnicity, public.profiles.ethnicity),
          date_of_birth = COALESCE(EXCLUDED.date_of_birth, public.profiles.date_of_birth),
          admin_created = admin_created_val,
          password_set = password_set_val,
          verified = COALESCE(verified_val, public.profiles.verified, CASE WHEN admin_created_val THEN true ELSE public.profiles.verified END),
          email_verified = COALESCE(email_verified_val, public.profiles.email_verified, CASE WHEN admin_created_val THEN true ELSE public.profiles.email_verified END),
          updated_at = NOW();

    RAISE WARNING 'Successfully created/updated profile for user %', NEW.id;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Failed to create/update profile for user %: %', NEW.id, SQLERRM;
  END;

  -- Create membership record
  BEGIN
    INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
    VALUES (NEW.id, user_role, 'automatic_signup', NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE
      SET role = COALESCE(EXCLUDED.role, public.memberships.role),
          gateway = COALESCE(EXCLUDED.gateway, public.memberships.gateway),
          updated_at = NOW();

    RAISE WARNING 'Successfully created/updated membership for user %', NEW.id;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Failed to create/update membership for user %: %', NEW.id, SQLERRM;
  END;

  -- Create trusted_partner record if needed
  IF user_type = 'trusted_partner' THEN
    BEGIN
      INSERT INTO public.trusted_partners (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, COALESCE(business_name, ''), NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;

      RAISE WARNING 'Successfully created trusted_partner record for user %', NEW.id;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to create trusted_partner record for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- =====================================================
-- STEP 3: Update business profile RPC to enable admin deal permissions
-- =====================================================

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
  v_logo_url text := nullif(coalesce(payload->>'logo_url', ''), '');

  v_latitude  double precision := public.try_cast_double(coalesce(payload->>'latitude', null));
  v_longitude double precision := public.try_cast_double(coalesce(payload->>'longitude', null));

  v_address text;
  v_business_id uuid;
  v_admin_created boolean := false;
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

  -- Create/update business record (NOW INCLUDING logo_url)
  INSERT INTO public.businesses (
    owner_member_id, name, category, address, latitude, longitude, contact_email, contact_number, logo_url, verified
  ) VALUES (
    uid, v_name, v_cat, v_address, v_latitude, v_longitude, v_contact_email, v_contact_number, v_logo_url, true
  ) ON CONFLICT (owner_member_id) DO UPDATE
    SET name = excluded.name,
        category = excluded.category,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        contact_email = excluded.contact_email,
        contact_number = excluded.contact_number,
        logo_url = excluded.logo_url,
        verified = true
        -- Note: Intentionally NOT overwriting allow_admin_deal_creation
        -- If it was set to true by admin creation, keep it true
  RETURNING id INTO v_business_id;

  -- If the user was admin-created, automatically allow admin deal creation for this business
  -- This ensures the permission is set even if business record already existed
  BEGIN
    SELECT admin_created INTO v_admin_created
    FROM public.profiles
    WHERE id = uid;

    IF coalesce(v_admin_created, false) THEN
      UPDATE public.businesses
      SET allow_admin_deal_creation = true
      WHERE id = v_business_id;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Non-fatal: policy mismatch or column missing; ignore
    PERFORM 1;
  END;

  RETURN jsonb_build_object('ok', true, 'business_id', v_business_id);

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$$;

-- =====================================================
-- STEP 4: Ensure allow_admin_deal_creation column exists
-- =====================================================

-- Add the column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'businesses' 
    AND column_name = 'allow_admin_deal_creation'
  ) THEN
    ALTER TABLE public.businesses
      ADD COLUMN allow_admin_deal_creation BOOLEAN NOT NULL DEFAULT false;
    
    COMMENT ON COLUMN public.businesses.allow_admin_deal_creation IS 'When true, admins may create discounts for this business on behalf of the owner.';
    
    CREATE INDEX idx_businesses_allow_admin_deal_creation
      ON public.businesses(allow_admin_deal_creation);
  END IF;
END $$;

-- =====================================================
-- STEP 5: Create RLS policies for admin deal creation/editing
-- =====================================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Admins can create discounts when allowed" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Admins can update discounts when allowed" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Admins can delete discounts when allowed" ON public.trusted_partner_discounts;

-- Create INSERT policy for admins
CREATE POLICY "Admins can create discounts when allowed" ON public.trusted_partner_discounts
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      JOIN public.businesses b
        ON b.id = trusted_partner_discounts.business_id
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
        AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
  );

-- Create UPDATE policy for admins
CREATE POLICY "Admins can update discounts when allowed" ON public.trusted_partner_discounts
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      JOIN public.businesses b
        ON b.id = trusted_partner_discounts.business_id
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
        AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      JOIN public.businesses b
        ON b.id = trusted_partner_discounts.business_id
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
        AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
  );

-- Create DELETE policy for admins
CREATE POLICY "Admins can delete discounts when allowed" ON public.trusted_partner_discounts
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      JOIN public.businesses b
        ON b.id = trusted_partner_discounts.business_id
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
        AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
  );

-- =====================================================
-- STEP 6: Add admin DELETE policies for profile management
-- =====================================================

-- Drop existing admin delete policy if it exists
DROP POLICY IF EXISTS "Admins can delete profiles" ON public.profiles;

-- Create DELETE policy for admins to manage user profiles
CREATE POLICY "Admins can delete profiles" ON public.profiles
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.memberships
      WHERE user_id = auth.uid()
      AND role = 'admin'
    )
  );

-- Also ensure admins can update profiles (needed for verification toggle)
DROP POLICY IF EXISTS "Admins can update profiles" ON public.profiles;

CREATE POLICY "Admins can update profiles" ON public.profiles
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.memberships
      WHERE user_id = auth.uid()
      AND role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.memberships
      WHERE user_id = auth.uid()
      AND role = 'admin'
    )
  );

-- =====================================================
-- STEP 7: Add admin RPC function for complete trusted partner deletion
-- =====================================================

-- This function deletes ALL related data for a trusted partner AND soft-deletes auth.users
-- The auth user is banned (inactive) and can only be reactivated by admin or via new signup
CREATE OR REPLACE FUNCTION public.admin_delete_trusted_partner_complete(tp_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  deleted_count JSONB;
  tp_email TEXT;
  business_ids UUID[];
BEGIN
  -- Verify the user is a trusted partner
  SELECT email INTO tp_email
  FROM public.profiles
  WHERE id = tp_user_id AND role = 'trusted_partner';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % is not a trusted partner or does not exist', tp_user_id;
  END IF;

  deleted_count := jsonb_build_object(
    'user_id', tp_user_id,
    'email', tp_email
  );

  -- Get all business IDs for this partner
  SELECT ARRAY_AGG(id) INTO business_ids
  FROM public.businesses
  WHERE owner_member_id = tp_user_id;

  -- Delete trusted_partner_discounts for all businesses owned by this partner
  IF business_ids IS NOT NULL THEN
    DELETE FROM public.trusted_partner_discounts WHERE business_id = ANY(business_ids);
    deleted_count := deleted_count || jsonb_build_object('discounts_deleted', true);
  END IF;

  -- Delete deal_authorizations for this partner's businesses
  IF business_ids IS NOT NULL THEN
    DELETE FROM public.deal_authorizations WHERE business_id = ANY(business_ids);
    deleted_count := deleted_count || jsonb_build_object('deal_authorizations_deleted', true);
  END IF;

  -- Delete processed_bills for this partner's businesses
  IF business_ids IS NOT NULL THEN
    DELETE FROM public.processed_bills WHERE business_id = ANY(business_ids);
    deleted_count := deleted_count || jsonb_build_object('processed_bills_deleted', true);
  END IF;

  -- Delete businesses
  DELETE FROM public.businesses WHERE owner_member_id = tp_user_id;
  deleted_count := deleted_count || jsonb_build_object('businesses_deleted', true);

  -- Delete trusted_partner record
  DELETE FROM public.trusted_partners WHERE user_id = tp_user_id;
  deleted_count := deleted_count || jsonb_build_object('trusted_partner_record_deleted', true);

  -- Delete payments
  DELETE FROM public.payments WHERE user_id = tp_user_id;
  deleted_count := deleted_count || jsonb_build_object('payments_deleted', true);

  -- Delete notifications
  DELETE FROM public.notifications WHERE user_id = tp_user_id;
  deleted_count := deleted_count || jsonb_build_object('notifications_deleted', true);

  -- Delete memberships
  DELETE FROM public.memberships WHERE user_id = tp_user_id;
  deleted_count := deleted_count || jsonb_build_object('memberships_deleted', true);

  -- Delete paystack_subaccounts if exists
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'paystack_subaccounts') THEN
    DELETE FROM public.paystack_subaccounts WHERE user_id = tp_user_id;
    deleted_count := deleted_count || jsonb_build_object('paystack_subaccounts_deleted', true);
  END IF;

  -- Delete partner_bank_accounts if exists
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'partner_bank_accounts') THEN
    DELETE FROM public.partner_bank_accounts WHERE user_id = tp_user_id;
    deleted_count := deleted_count || jsonb_build_object('bank_accounts_deleted', true);
  END IF;

  -- Finally delete profile
  DELETE FROM public.profiles WHERE id = tp_user_id;
  deleted_count := deleted_count || jsonb_build_object('profile_deleted', true);

  -- Soft-delete from auth.users: Ban the user (make inactive) instead of hard delete
  -- This prevents login but preserves the auth record for potential reactivation
  UPDATE auth.users 
  SET 
    banned_until = 'infinity'::timestamptz,  -- Ban indefinitely
    deleted_at = NOW(),                       -- Mark as deleted (soft delete)
    updated_at = NOW()
  WHERE id = tp_user_id;

  deleted_count := deleted_count || jsonb_build_object(
    'auth_user_banned', true,
    'auth_user_status', 'inactive',
    'note', 'User is banned and cannot login. Can be reactivated by admin or via new signup.'
  );

  RETURN deleted_count::json;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to delete trusted partner data: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_trusted_partner_complete(UUID) TO authenticated;

-- =====================================================
-- VERIFICATION QUERIES (run after applying above)
-- =====================================================

-- Check if RPC exists
SELECT 'admin_create_trusted_partner function:' as check_type, 
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc WHERE proname = 'admin_create_trusted_partner'
       ) THEN '✅ EXISTS' ELSE '❌ MISSING' END as status;

-- Check if column exists
SELECT 'allow_admin_deal_creation column:' as check_type,
       CASE WHEN EXISTS (
         SELECT 1 FROM information_schema.columns 
         WHERE table_name = 'businesses' AND column_name = 'allow_admin_deal_creation'
       ) THEN '✅ EXISTS' ELSE '❌ MISSING' END as status;

-- Check if policies exist
SELECT 'Admin deal policies:' as check_type,
       COUNT(*)::text || ' policies created' as status
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename = 'trusted_partner_discounts'
  AND policyname LIKE '%Admins can%';

-- Check if admin profile management policies exist
SELECT 'Admin profile policies:' as check_type,
       CASE 
         WHEN COUNT(*) >= 2 THEN '✅ ' || COUNT(*)::text || ' admin profile policies created'
         ELSE '⚠️ Only ' || COUNT(*)::text || ' admin profile policy/policies found'
       END as status
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename = 'profiles'
  AND (policyname LIKE '%Admins can delete%' OR policyname LIKE '%Admins can update%');

-- Check if admin delete function exists
SELECT 'Admin delete function:' as check_type,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc WHERE proname = 'admin_delete_trusted_partner_complete'
       ) THEN '✅ EXISTS' ELSE '❌ MISSING' END as status;

-- Check if required columns exist in profiles
SELECT 'Profile columns:' as check_type,
       string_agg(column_name, ', ') as status
FROM information_schema.columns 
WHERE table_name = 'profiles' 
  AND column_name IN ('admin_created', 'email_verified', 'verified', 'password_set');

-- Check if business record gets created with admin permissions (check recent admin-created partners)
SELECT 'Business record creation:' as check_type,
       CASE 
         WHEN EXISTS (
           SELECT 1 
           FROM businesses b
           JOIN profiles p ON p.id = b.owner_member_id
           WHERE p.admin_created = true
           AND b.allow_admin_deal_creation = true
         ) THEN '✅ ' || COUNT(*)::text || ' admin-created business(es) found with permission enabled'
         ELSE '⚠️ No admin-created businesses found yet - create test partner to verify'
       END as status
FROM businesses b
JOIN profiles p ON p.id = b.owner_member_id
WHERE p.admin_created = true
AND b.allow_admin_deal_creation = true;

-- Detailed verification: Show recent admin-created partners with business details
SELECT 
  '--- Admin-Created Partners Details ---' as info,
  p.email,
  p.admin_created,
  p.verified as profile_verified,
  p.email_verified,
  b.name as business_name,
  b.category,
  b.allow_admin_deal_creation,
  b.verified as business_verified,
  b.created_at
FROM profiles p
LEFT JOIN businesses b ON b.owner_member_id = p.id
WHERE p.admin_created = true
ORDER BY p.created_at DESC
LIMIT 5;

-- Verify partners show in verified tab (profiles with verified=true AND role=trusted_partner)
SELECT 'Verified tab visibility:' as check_type,
       CASE 
         WHEN EXISTS (
           SELECT 1 
           FROM profiles 
           WHERE admin_created = true 
           AND role = 'trusted_partner'
           AND verified = true
         ) THEN '✅ ' || COUNT(*)::text || ' admin-created partner(s) will appear in Verified tab'
         ELSE '⚠️ No verified admin-created partners found yet'
       END as status
FROM profiles
WHERE admin_created = true 
AND role = 'trusted_partner'
AND verified = true;

-- =====================================================
-- DONE! 
-- All SQL has been applied successfully if verification queries show ✅
-- 
-- IMPORTANT: After admin creates a trusted partner:
-- 1. Profile is created with verified=true (appears in Verified tab)
-- 2. Business record is created immediately with verified=true and allow_admin_deal_creation=true
-- 3. Admin can create deals right away without waiting for profile completion
-- 4. Partner appears in the "Verified" tab in admin view trusted partners screen
-- 5. Partner can later complete their business profile to update details
-- 
-- ADMIN DELETION:
-- To delete a trusted partner, use the RPC function:
--   SELECT admin_delete_trusted_partner_complete('user-uuid-here');
-- 
-- This will delete from ALL related tables:
-- - trusted_partner_discounts (all deals)
-- - deal_authorizations
-- - processed_bills
-- - businesses
-- - trusted_partners
-- - payments
-- - notifications
-- - memberships
-- - paystack_subaccounts (if exists)
-- - partner_bank_accounts (if exists)
-- - profiles
-- - auth.users (SOFT DELETE - banned indefinitely, marked as deleted)
-- 
-- SOFT DELETE BEHAVIOR:
-- The auth.users record is NOT hard-deleted. Instead:
-- - banned_until = 'infinity' (user cannot login)
-- - deleted_at = NOW() (marked as deleted for tracking)
-- - User cannot authenticate or access the app
-- - User can be reactivated by:
--   1. Admin manually unbanning: UPDATE auth.users SET banned_until = NULL, deleted_at = NULL WHERE id = 'user-id';
--   2. User signing up again with same email (creates new auth record)
-- 
-- VERIFICATION:
-- Run this script and check the verification queries to see:
-- - Count of admin-created businesses with permission enabled
-- - Details of recent admin-created partners and their business records
-- - Confirmation that partners appear in the Verified tab
-- - Confirmation that admin delete function exists
-- =====================================================
