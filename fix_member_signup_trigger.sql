-- FIX: Member signup "Database error saving new user" (500)
-- Root cause: CHECK constraint on profiles.role may only allow ('user','merchant','admin')
--             but trigger inserts 'member'. Also fixes date_of_birth type mismatch.
-- Run this ENTIRE script in Supabase SQL Editor

BEGIN;

-- ============================================================
-- Step 1: Fix role CHECK constraints to allow correct values
-- ============================================================
-- Drop ALL old role constraints (there may be multiple from previous migrations)
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS valid_role;
ALTER TABLE public.memberships DROP CONSTRAINT IF EXISTS valid_membership_role;
ALTER TABLE public.memberships DROP CONSTRAINT IF EXISTS memberships_role_check;

-- Update any legacy 'user' roles to 'member'
UPDATE public.profiles SET role = 'member' WHERE role = 'user';
UPDATE public.memberships SET role = 'member' WHERE role = 'user';

-- Update any legacy 'merchant' roles to 'trusted_partner'
UPDATE public.profiles SET role = 'trusted_partner' WHERE role = 'merchant';
UPDATE public.memberships SET role = 'trusted_partner' WHERE role = 'merchant';

-- Set correct default
ALTER TABLE public.profiles ALTER COLUMN role SET DEFAULT 'member';

-- Add constraints with the CORRECT role values
ALTER TABLE public.profiles 
  ADD CONSTRAINT valid_role CHECK (role IN ('member', 'trusted_partner', 'admin'));

ALTER TABLE public.memberships 
  ADD CONSTRAINT valid_membership_role CHECK (role IN ('member', 'trusted_partner', 'admin'));

-- ============================================================
-- Step 2: Ensure all required columns exist on profiles table
-- ============================================================
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS gender TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS ethnicity TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS admin_created BOOLEAN DEFAULT FALSE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS password_set BOOLEAN DEFAULT TRUE;

-- ============================================================
-- Step 3: Replace the trigger function with a robust version
-- ============================================================
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
  dob_value timestamptz;
BEGIN
  -- Get user_type from metadata (raw_user_meta_data is where signInWithOtp stores data)
  user_type := COALESCE(
    NEW.raw_user_meta_data->>'user_type',
    NEW.raw_app_meta_data->>'user_type'
  );

  user_email := COALESCE(NEW.email, NEW.raw_user_meta_data->>'email', '');

  user_name := COALESCE(
    NEW.raw_user_meta_data->>'name',
    NEW.raw_app_meta_data->>'name'
  );

  user_surname := COALESCE(
    NEW.raw_user_meta_data->>'surname',
    NEW.raw_app_meta_data->>'surname'
  );

  business_name := COALESCE(
    NEW.raw_user_meta_data->>'business_name',
    NEW.raw_app_meta_data->>'business_name'
  );

  -- Map user_type to role
  IF user_type = 'trusted_partner' OR user_type = 'merchant' THEN
    user_role := 'trusted_partner';
  ELSIF user_type = 'admin' THEN
    user_role := 'admin';
  ELSE
    user_role := 'member';  -- Default to member
  END IF;

  -- Safely parse date_of_birth
  dob_text := COALESCE(
    NEW.raw_user_meta_data->>'date_of_birth',
    NEW.raw_app_meta_data->>'date_of_birth'
  );
  
  IF dob_text IS NOT NULL AND dob_text != '' THEN
    BEGIN
      dob_value := dob_text::timestamptz;
    EXCEPTION
      WHEN OTHERS THEN
        dob_value := NULL;
        RAISE WARNING 'Trigger: Could not parse date_of_birth "%": %', dob_text, SQLERRM;
    END;
  END IF;

  -- Create profile record
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
      COALESCE(NEW.raw_user_meta_data->>'street', NEW.raw_app_meta_data->>'street'),
      COALESCE(NEW.raw_user_meta_data->>'suburb', NEW.raw_app_meta_data->>'suburb'),
      COALESCE(NEW.raw_user_meta_data->>'city', NEW.raw_app_meta_data->>'city'),
      COALESCE(NEW.raw_user_meta_data->>'province', NEW.raw_app_meta_data->>'province'),
      COALESCE(NEW.raw_user_meta_data->>'contact', NEW.raw_app_meta_data->>'contact'),
      COALESCE(NEW.raw_user_meta_data->>'gender', NEW.raw_app_meta_data->>'gender'),
      COALESCE(NEW.raw_user_meta_data->>'ethnicity', NEW.raw_app_meta_data->>'ethnicity'),
      dob_value,
      CASE
        WHEN NEW.raw_user_meta_data->>'admin_created' = 'true' THEN true
        WHEN NEW.raw_app_meta_data->>'admin_created' = 'true' THEN true
        ELSE false
      END,
      CASE
        WHEN NEW.raw_user_meta_data->>'password_set' = 'false' THEN false
        WHEN NEW.raw_app_meta_data->>'password_set' = 'false' THEN false
        ELSE true
      END,
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
          admin_created = COALESCE(EXCLUDED.admin_created, public.profiles.admin_created),
          password_set = COALESCE(EXCLUDED.password_set, public.profiles.password_set),
          updated_at = NOW();

    RAISE WARNING 'Trigger: Profile created/updated for user % with role %', NEW.id, user_role;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Trigger: Failed to create profile for user %: %', NEW.id, SQLERRM;
  END;

  -- Insert into memberships table
  BEGIN
    INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
    VALUES (NEW.id, user_role, 'automatic_signup', NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE
      SET role = COALESCE(EXCLUDED.role, public.memberships.role),
          gateway = COALESCE(EXCLUDED.gateway, public.memberships.gateway),
          updated_at = NOW();
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Trigger: Failed to create membership for user %: %', NEW.id, SQLERRM;
  END;

  -- Create trusted_partner record if needed
  IF user_type = 'trusted_partner' OR user_type = 'merchant' THEN
    BEGIN
      INSERT INTO public.trusted_partners (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, COALESCE(business_name, ''), NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'Trigger: Failed to create trusted_partner for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- Step 4: Ensure the trigger exists (recreate if needed)
-- ============================================================
DROP TRIGGER IF EXISTS trigger_automatic_role_assignment ON auth.users;
CREATE TRIGGER trigger_automatic_role_assignment
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user_role_assignment();

COMMIT;

-- ============================================================
-- Step 5: Verify everything
-- ============================================================
SELECT 'Fix applied successfully' AS status;

-- Show current role constraints
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.profiles'::regclass
  AND contype = 'c';

-- Show current role default
SELECT column_name, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'role';
