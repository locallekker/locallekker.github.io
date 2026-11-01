-- Migration: Simplify trigger to avoid database errors
-- This migration creates a simpler trigger that only handles the basic fields

BEGIN;

-- Create a simpler trigger function that handles errors more gracefully
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
  -- Get basic user information
  user_email := COALESCE(NEW.email, '');

  -- Try to get user_type from different metadata locations
  user_type := COALESCE(
    NEW.raw_app_meta_data->>'user_type',
    NEW.raw_user_meta_data->>'user_type',
    NEW.user_metadata->>'user_type'
  );

  -- Determine role
  IF user_type = 'merchant' THEN
    user_role := 'merchant';
  ELSE
    user_role := 'user';
  END IF;

  -- Get name and surname if available
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

  -- Insert basic profile information only
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
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      user_email,
      user_role,
      user_name,
      user_surname,
      COALESCE(NEW.raw_app_meta_data->>'street', NEW.raw_user_meta_data->>'street', NEW.user_metadata->>'street'),
      COALESCE(NEW.raw_app_meta_data->>'suburb', NEW.raw_user_meta_data->>'suburb', NEW.user_metadata->>'suburb'),
      COALESCE(NEW.raw_app_meta_data->>'city', NEW.raw_user_meta_data->>'city', NEW.user_metadata->>'city'),
      COALESCE(NEW.raw_app_meta_data->>'province', NEW.raw_user_meta_data->>'province', NEW.user_metadata->>'province'),
      COALESCE(NEW.raw_app_meta_data->>'contact', NEW.raw_user_meta_data->>'contact', NEW.user_metadata->>'contact'),
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
          updated_at = NOW();

    RAISE WARNING 'Profile created/updated successfully for user %', NEW.id;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Failed to create/update profile for user %: %', NEW.id, SQLERRM;
      -- Don't fail the user creation, just log the error
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

  RETURN NEW;
END;
$$;

COMMIT;