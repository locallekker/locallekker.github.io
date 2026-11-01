-- Migration: Fix member signup trigger to use 'member' role instead of 'user'
-- The profiles table CHECK constraint only allows: 'member', 'trusted_partner', 'admin'
-- But the trigger was setting role to 'user' for members, causing signup failures

BEGIN;

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
BEGIN
  -- Get user_type from metadata
  user_type := NEW.raw_app_meta_data->>'user_type';

  IF user_type IS NULL THEN
    user_type := NEW.raw_user_meta_data->>'user_type';
  END IF;

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

  -- Map user_type to role (FIX: use 'member' instead of 'user')
  IF user_type = 'merchant' THEN
    user_role := 'trusted_partner'; -- Merchants are now called trusted_partners
  ELSIF user_type = 'trusted_partner' THEN
    user_role := 'trusted_partner';
  ELSIF user_type = 'member' THEN
    user_role := 'member';
  ELSE
    user_role := 'member'; -- DEFAULT to 'member' instead of 'user'
  END IF;

  RAISE WARNING 'Trigger Debug - raw_app_meta_data: %', NEW.raw_app_meta_data::text;
  RAISE WARNING 'Trigger Debug - raw_user_meta_data: %', NEW.raw_user_meta_data::text;
  RAISE WARNING 'Trigger Debug - user_type: %, role: %, name: %, surname: %', user_type, user_role, user_name, user_surname;

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
      created_at,
      updated_at
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
      CASE
        WHEN COALESCE(NEW.raw_app_meta_data->>'date_of_birth', NEW.raw_user_meta_data->>'date_of_birth') IS NOT NULL
        THEN (COALESCE(NEW.raw_app_meta_data->>'date_of_birth', NEW.raw_user_meta_data->>'date_of_birth'))::timestamp with time zone
        ELSE NULL
      END,
      CASE 
        WHEN NEW.raw_app_meta_data->>'admin_created' = 'true' OR NEW.raw_user_meta_data->>'admin_created' = 'true' THEN true
        WHEN NEW.raw_app_meta_data->>'admin_created' = 'false' OR NEW.raw_user_meta_data->>'admin_created' = 'false' THEN false
        ELSE false
      END,
      CASE 
        WHEN NEW.raw_app_meta_data->>'password_set' = 'true' OR NEW.raw_user_meta_data->>'password_set' = 'true' THEN true
        WHEN NEW.raw_app_meta_data->>'password_set' = 'false' OR NEW.raw_user_meta_data->>'password_set' = 'false' THEN false
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
          admin_created = CASE 
            WHEN NEW.raw_app_meta_data->>'admin_created' = 'true' OR NEW.raw_user_meta_data->>'admin_created' = 'true' THEN true
            WHEN NEW.raw_app_meta_data->>'admin_created' = 'false' OR NEW.raw_user_meta_data->>'admin_created' = 'false' THEN false
            ELSE COALESCE(EXCLUDED.admin_created, public.profiles.admin_created)
          END,
          password_set = CASE 
            WHEN NEW.raw_app_meta_data->>'password_set' = 'true' OR NEW.raw_user_meta_data->>'password_set' = 'true' THEN true
            WHEN NEW.raw_app_meta_data->>'password_set' = 'false' OR NEW.raw_user_meta_data->>'password_set' = 'false' THEN false
            ELSE COALESCE(EXCLUDED.password_set, public.profiles.password_set)
          END,
          updated_at = NOW();
    RAISE WARNING 'Trigger: Profile created/updated for user % with role %', NEW.id, user_role;
  EXCEPTION
    WHEN OTHERS THEN
      -- Log error but don't fail the user creation
      RAISE WARNING 'Trigger: Failed to create/update profile for user %: %', NEW.id, SQLERRM;
  END;

  -- Insert into memberships table
  BEGIN
    INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
    VALUES (NEW.id, user_role, 'automatic_signup', NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE
      SET role = COALESCE(EXCLUDED.role, public.memberships.role),
          gateway = COALESCE(EXCLUDED.gateway, public.memberships.gateway),
          updated_at = NOW();
    RAISE WARNING 'Trigger: Membership created/updated for user %', NEW.id;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Trigger: Failed to create/update membership for user %: %', NEW.id, SQLERRM;
  END;

  -- Create merchant record if needed (legacy support)
  IF user_type = 'merchant' THEN
    BEGIN
      INSERT INTO public.merchants (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, '', NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'Trigger: Failed to create merchant record for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  -- Create trusted_partner record if needed
  IF user_type = 'trusted_partner' OR user_type = 'merchant' THEN
    BEGIN
      INSERT INTO public.trusted_partners (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, COALESCE(business_name, ''), NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
      RAISE WARNING 'Trigger: Trusted partner record created for user %', NEW.id;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'Trigger: Failed to create trusted_partner record for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

COMMIT;
