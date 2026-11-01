
-- Update trigger to handle metadata more robustly and add better error handling
-- This ensures trusted partner creation works correctly

BEGIN;

CREATE OR REPLACE FUNCTION public.handle_new_user_role_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS \$\$
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
\$\$;

COMMIT;

