-- Migration: Create automatic role assignment trigger
-- Creates a trigger that automatically assigns roles based on user_type metadata
-- when new users are created in auth.users

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

  IF user_type = 'merchant' THEN
    user_role := 'merchant';
  ELSIF user_type = 'trusted_partner' THEN
    user_role := 'trusted_partner';
  ELSE
    user_role := 'user';
  END IF;

  RAISE WARNING 'Trigger Debug - raw_app_meta_data: %', NEW.raw_app_meta_data::text;
  RAISE WARNING 'Trigger Debug - raw_user_meta_data: %', NEW.raw_user_meta_data::text;
  RAISE WARNING 'Trigger Debug - user_type: %, name: %, surname: %', user_type, user_name, user_surname;

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
      COALESCE(user_role, 'user'),
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
      COALESCE((NEW.raw_app_meta_data->>'admin_created')::boolean, (NEW.raw_user_meta_data->>'admin_created')::boolean, false),
      COALESCE((NEW.raw_app_meta_data->>'password_set')::boolean, (NEW.raw_user_meta_data->>'password_set')::boolean, true),
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
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Failed to create/update profile for user %: %', NEW.id, SQLERRM;
  END;

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

  IF user_type = 'trusted_partner' THEN
    BEGIN
      INSERT INTO public.trusted_partners (user_id, business_name, created_at, updated_at)
      VALUES (NEW.id, COALESCE(business_name, ''), NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'Failed to create trusted_partner record for user %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_automatic_role_assignment ON auth.users;
CREATE TRIGGER trigger_automatic_role_assignment
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user_role_assignment();

COMMIT;