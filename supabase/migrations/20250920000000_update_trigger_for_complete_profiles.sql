-- Migration: Update trigger to populate all profile fields from user metadata
-- This updates the existing trigger function to include all user profile fields

BEGIN;

-- Update the function to handle automatic role assignment with complete profile data
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
BEGIN
  -- Get user_type from raw_app_meta_data
  user_type := NEW.raw_app_meta_data->>'user_type';

  -- If not found in raw_app_meta_data, try raw_user_meta_data
  IF user_type IS NULL THEN
    user_type := NEW.raw_user_meta_data->>'user_type';
  END IF;

  -- Get user email
  user_email := COALESCE(NEW.email, NEW.raw_user_meta_data->>'email', '');

  -- Get user name and surname from metadata
  user_name := NEW.raw_app_meta_data->>'name';
  user_surname := NEW.raw_app_meta_data->>'surname';

  -- Determine role based on user_type
  IF user_type = 'merchant' THEN
    user_role := 'merchant';
  ELSE
    -- Default to 'user' role for any other type or null
    user_role := 'user';
  END IF;

  -- Log the user_type and role assignment for debugging
  RAISE WARNING 'Trigger: user_type=% role=% email=%', user_type, user_role, user_email;

  -- Insert into profiles table with ALL available data from user metadata
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
      user_role,
      user_name,
      user_surname,
      NEW.raw_app_meta_data->>'street',
      NEW.raw_app_meta_data->>'suburb',
      NEW.raw_app_meta_data->>'city',
      NEW.raw_app_meta_data->>'province',
      NEW.raw_app_meta_data->>'contact',
      NEW.raw_app_meta_data->>'gender',
      NEW.raw_app_meta_data->>'ethnicity',
      (NEW.raw_app_meta_data->>'date_of_birth')::timestamp with time zone,
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
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but don't fail the user creation
      RAISE WARNING 'Failed to create/update profile for user %: %', NEW.id, SQLERRM;
  END;

  -- Insert into memberships table with better error handling
  BEGIN
    INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
    VALUES (NEW.id, user_role, 'automatic_signup', NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE
      SET role = COALESCE(EXCLUDED.role, public.memberships.role),
          gateway = COALESCE(EXCLUDED.gateway, public.memberships.gateway),
          updated_at = NOW();
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but don't fail the user creation
      RAISE WARNING 'Failed to create/update membership for user %: %', NEW.id, SQLERRM;
  END;

  -- If merchant, also create a merchants record with error handling
  IF user_type = 'merchant' THEN
    BEGIN
      INSERT INTO public.merchants (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, '', NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION
      WHEN OTHERS THEN
        -- Log error but don't fail the user creation
        RAISE WARNING 'Failed to create merchant record for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

COMMIT;