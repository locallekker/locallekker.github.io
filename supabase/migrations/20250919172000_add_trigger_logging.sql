-- Migration: Add logging to trigger for debugging role assignment
-- Adds warning logs to help debug why roles are not being assigned correctly

BEGIN;

-- Update the function to add logging for debugging
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
BEGIN
  -- Get user_type from raw_app_meta_data (set during signup)
  user_type := NEW.raw_app_meta_data->>'user_type';

  -- If not found in raw_app_meta_data, try raw_user_meta_data
  IF user_type IS NULL THEN
    user_type := NEW.raw_user_meta_data->>'user_type';
  END IF;

  -- Get user email
  user_email := COALESCE(NEW.email, NEW.raw_user_meta_data->>'email', '');

  -- Determine role based on user_type
  IF user_type = 'merchant' THEN
    user_role := 'merchant';
  ELSE
    -- Default to 'user' role for any other type or null
    user_role := 'user';
  END IF;

  -- Log the user_type and role assignment for debugging
  RAISE WARNING 'Trigger: user_id=% user_type=% role=% email=%', NEW.id, user_type, user_role, user_email;

  -- Insert into profiles table with better error handling
  BEGIN
    INSERT INTO public.profiles (id, email, role, created_at, updated_at)
    VALUES (NEW.id, user_email, user_role, NOW(), NOW())
    ON CONFLICT (id) DO UPDATE
      SET email = COALESCE(EXCLUDED.email, public.profiles.email),
          role = COALESCE(EXCLUDED.role, public.profiles.role),
          updated_at = NOW();
    RAISE WARNING 'Trigger: Profile created/updated for user % with role %', NEW.id, user_role;
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but don't fail the user creation
      RAISE WARNING 'Trigger: Failed to create/update profile for user %: %', NEW.id, SQLERRM;
  END;

  -- Insert into memberships table with better error handling
  BEGIN
    INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
    VALUES (NEW.id, user_role, 'automatic_signup', NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE
      SET role = COALESCE(EXCLUDED.role, public.memberships.role),
          gateway = COALESCE(EXCLUDED.gateway, public.memberships.gateway),
          updated_at = NOW();
    RAISE WARNING 'Trigger: Membership created/updated for user % with role %', NEW.id, user_role;
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but don't fail the user creation
      RAISE WARNING 'Trigger: Failed to create/update membership for user %: %', NEW.id, SQLERRM;
  END;

  -- If merchant, also create a merchants record with error handling
  IF user_type = 'merchant' THEN
    BEGIN
      INSERT INTO public.merchants (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, '', NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
      RAISE WARNING 'Trigger: Merchant record created for user %', NEW.id;
    EXCEPTION
      WHEN OTHERS THEN
        -- Log error but don't fail the user creation
        RAISE WARNING 'Trigger: Failed to create merchant record for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

COMMIT;