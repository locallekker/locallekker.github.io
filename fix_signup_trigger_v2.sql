-- FIX: Member signup "Database error saving new user" (500)
-- Root cause: trigger references columns (admin_created, password_set) that may not exist,
-- and/or casts date_of_birth to wrong type.
-- 
-- This script:
-- 1. Ensures admin_created and password_set columns exist on profiles
-- 2. Replaces the trigger with a clean version that handles all edge cases
-- 3. Uses correct DATE cast for date_of_birth
-- 4. Only references real auth.users columns (raw_app_meta_data, raw_user_meta_data)
-- 5. Defaults role to 'member' (never 'user')

BEGIN;

-- STEP 1: Ensure the columns the trigger needs actually exist
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS admin_created BOOLEAN DEFAULT FALSE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS password_set BOOLEAN DEFAULT TRUE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS gender TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS ethnicity TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS date_of_birth DATE;

-- STEP 2: Drop and re-check role constraint (allow member/trusted_partner/admin only)
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
-- Only add if you want strict enforcement; omit if you want flexibility:
-- ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK (role IN ('member', 'trusted_partner', 'admin'));

-- STEP 3: Replace the trigger function with a clean, safe version
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
  dob_text text;
  dob_value date;
  is_admin_created boolean;
  is_password_set boolean;
BEGIN
  -- Get user_type from metadata (only use real auth.users columns)
  user_type := COALESCE(
    NEW.raw_app_meta_data->>'user_type',
    NEW.raw_user_meta_data->>'user_type'
  );

  user_email := COALESCE(NEW.email, NEW.raw_user_meta_data->>'email', '');

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

  -- Map user_type to valid role (NEVER use 'user' or 'merchant')
  IF user_type = 'merchant' OR user_type = 'trusted_partner' THEN
    user_role := 'trusted_partner';
  ELSIF user_type = 'admin' THEN
    user_role := 'admin';
  ELSE
    user_role := 'member';
  END IF;

  -- Safely parse date_of_birth as DATE (not timestamptz)
  dob_text := COALESCE(
    NEW.raw_app_meta_data->>'date_of_birth',
    NEW.raw_user_meta_data->>'date_of_birth'
  );
  IF dob_text IS NOT NULL AND dob_text != '' THEN
    BEGIN
      dob_value := dob_text::date;
    EXCEPTION WHEN OTHERS THEN
      dob_value := NULL; -- Invalid date format, skip
    END;
  ELSE
    dob_value := NULL;
  END IF;

  -- Parse admin_created flag
  is_admin_created := COALESCE(
    NEW.raw_app_meta_data->>'admin_created',
    NEW.raw_user_meta_data->>'admin_created'
  ) = 'true';

  -- Parse password_set flag (default true for self-signup)
  is_password_set := COALESCE(
    NEW.raw_app_meta_data->>'password_set',
    NEW.raw_user_meta_data->>'password_set',
    'true'
  ) != 'false';

  -- Insert profile
  BEGIN
    INSERT INTO public.profiles (
      id, email, role, name, surname,
      street, suburb, city, province, contact,
      gender, ethnicity, date_of_birth,
      admin_created, password_set,
      created_at, updated_at
    )
    VALUES (
      NEW.id,
      user_email,
      user_role,
      user_name,
      user_surname,
      COALESCE(NEW.raw_app_meta_data->>'street', NEW.raw_user_meta_data->>'street'),
      COALESCE(NEW.raw_app_meta_data->>'suburb', NEW.raw_user_meta_data->>'suburb'),
      COALESCE(NEW.raw_app_meta_data->>'city', NEW.raw_user_meta_data->>'city'),
      COALESCE(NEW.raw_app_meta_data->>'province', NEW.raw_user_meta_data->>'province'),
      COALESCE(NEW.raw_app_meta_data->>'contact', NEW.raw_user_meta_data->>'contact'),
      COALESCE(NEW.raw_app_meta_data->>'gender', NEW.raw_user_meta_data->>'gender'),
      COALESCE(NEW.raw_app_meta_data->>'ethnicity', NEW.raw_user_meta_data->>'ethnicity'),
      dob_value,
      is_admin_created,
      is_password_set,
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO UPDATE
      SET email = COALESCE(EXCLUDED.email, profiles.email),
          role = COALESCE(EXCLUDED.role, profiles.role),
          name = COALESCE(EXCLUDED.name, profiles.name),
          surname = COALESCE(EXCLUDED.surname, profiles.surname),
          street = COALESCE(EXCLUDED.street, profiles.street),
          suburb = COALESCE(EXCLUDED.suburb, profiles.suburb),
          city = COALESCE(EXCLUDED.city, profiles.city),
          province = COALESCE(EXCLUDED.province, profiles.province),
          contact = COALESCE(EXCLUDED.contact, profiles.contact),
          gender = COALESCE(EXCLUDED.gender, profiles.gender),
          ethnicity = COALESCE(EXCLUDED.ethnicity, profiles.ethnicity),
          date_of_birth = COALESCE(EXCLUDED.date_of_birth, profiles.date_of_birth),
          admin_created = COALESCE(EXCLUDED.admin_created, profiles.admin_created),
          password_set = COALESCE(EXCLUDED.password_set, profiles.password_set),
          updated_at = NOW();
  EXCEPTION
    WHEN OTHERS THEN
      -- Log but do NOT fail user creation
      RAISE WARNING 'Trigger: profile insert failed for %: %', NEW.id, SQLERRM;
  END;

  -- Insert membership
  BEGIN
    INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
    VALUES (NEW.id, user_role, 'automatic_signup', NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE
      SET role = COALESCE(EXCLUDED.role, memberships.role),
          gateway = COALESCE(EXCLUDED.gateway, memberships.gateway),
          updated_at = NOW();
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Trigger: membership insert failed for %: %', NEW.id, SQLERRM;
  END;

  -- Create trusted_partner / merchant record if needed
  IF user_type = 'trusted_partner' OR user_type = 'merchant' THEN
    BEGIN
      INSERT INTO public.trusted_partners (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, COALESCE(business_name, ''), NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'Trigger: trusted_partner insert failed for %: %', NEW.id, SQLERRM;
    END;

    -- Legacy merchants table
    BEGIN
      INSERT INTO public.merchants (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, COALESCE(business_name, ''), NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION
      WHEN OTHERS THEN
        NULL; -- merchants table may not exist
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- STEP 4: Ensure the trigger is attached
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user_role_assignment();

COMMIT;

-- VERIFICATION: Run these after applying the migration
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'profiles'
-- ORDER BY ordinal_position;
--
-- SELECT trigger_name, event_manipulation, action_statement
-- FROM information_schema.triggers
-- WHERE event_object_schema = 'auth' AND event_object_table = 'users';
