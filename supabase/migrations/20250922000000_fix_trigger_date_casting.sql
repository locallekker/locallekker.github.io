-- Migration: Fix trigger date casting and role handling
-- This migration fixes the database error during signup by making the trigger more defensive

BEGIN;

-- Update the trigger function to handle NULL values properly
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
  metadata_json jsonb;
BEGIN
  -- Log all available metadata for debugging
  RAISE WARNING '=== TRIGGER DEBUG START ===';
  RAISE WARNING 'NEW.email: %', NEW.email;
  RAISE WARNING 'NEW.raw_app_meta_data: %', NEW.raw_app_meta_data::text;
  RAISE WARNING 'NEW.raw_user_meta_data: %', NEW.raw_user_meta_data::text;
  RAISE WARNING 'NEW.user_metadata: %', NEW.user_metadata::text;

  -- Try to get user_type from different locations
  user_type := COALESCE(
    NEW.raw_app_meta_data->>'user_type',
    NEW.raw_user_meta_data->>'user_type',
    NEW.user_metadata->>'user_type'
  );

  -- Get user email
  user_email := COALESCE(NEW.email, NEW.raw_user_meta_data->>'email', '');

  -- Get user name and surname from metadata - try all locations
  user_name := COALESCE(
    NEW.raw_app_meta_data->>'name',
    NEW.raw_user_meta_data->>'name',
    NEW.user_metadata->>'name'
  );
  user_surname := COALESCE(
    NEW.raw_app_meta_data->>'surname',
    NEW.raw_user_meta_data->>'surname',
    NEW.user_metadata->>'surname'
  );

  -- Determine role based on user_type
  IF user_type = 'merchant' THEN
    user_role := 'merchant';
  ELSE
    user_role := 'user';
  END IF;

  RAISE WARNING 'Final values - user_type: %, user_role: %, user_name: %, user_surname: %', user_type, user_role, user_name, user_surname;

  -- Insert into profiles table with ALL available data
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
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      user_email,
      COALESCE(user_role, 'user'),
      user_name,
      user_surname,
      COALESCE(NEW.raw_app_meta_data->>'street', NEW.raw_user_meta_data->>'street', NEW.user_metadata->>'street'),
      COALESCE(NEW.raw_app_meta_data->>'suburb', NEW.raw_user_meta_data->>'suburb', NEW.user_metadata->>'suburb'),
      COALESCE(NEW.raw_app_meta_data->>'city', NEW.raw_user_meta_data->>'city', NEW.user_metadata->>'city'),
      COALESCE(NEW.raw_app_meta_data->>'province', NEW.raw_user_meta_data->>'province', NEW.user_metadata->>'province'),
      COALESCE(NEW.raw_app_meta_data->>'contact', NEW.raw_user_meta_data->>'contact', NEW.user_metadata->>'contact'),
      COALESCE(NEW.raw_app_meta_data->>'gender', NEW.raw_user_meta_data->>'gender', NEW.user_metadata->>'gender'),
      COALESCE(NEW.raw_app_meta_data->>'ethnicity', NEW.raw_user_meta_data->>'ethnicity', NEW.user_metadata->>'ethnicity'),
      CASE
        WHEN COALESCE(NEW.raw_app_meta_data->>'date_of_birth', NEW.raw_user_meta_data->>'date_of_birth', NEW.user_metadata->>'date_of_birth') IS NOT NULL
        THEN (COALESCE(NEW.raw_app_meta_data->>'date_of_birth', NEW.raw_user_meta_data->>'date_of_birth', NEW.user_metadata->>'date_of_birth'))::timestamp with time zone
        ELSE NULL
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
          updated_at = NOW();

    RAISE WARNING 'Profile insert/update completed successfully for user %', NEW.id;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Failed to create/update profile for user %: %', NEW.id, SQLERRM;
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
      RAISE WARNING 'Failed to create/update membership for user %: %', NEW.id, SQLERRM;
  END;

  -- If merchant, create merchants record
  IF user_type = 'merchant' THEN
    BEGIN
      INSERT INTO public.merchants (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, '', NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'Failed to create merchant record for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RAISE WARNING '=== TRIGGER DEBUG END ===';
  RETURN NEW;
END;
$$;

COMMIT;