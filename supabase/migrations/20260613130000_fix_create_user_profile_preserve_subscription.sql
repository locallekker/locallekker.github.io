-- Hotfix: preserve existing subscription status on create_user_profile UPSERT
-- Reason: fallback profile updates for existing members could overwrite
-- subscriptions to 'pending', while TP-member paths remained 'active'.

CREATE OR REPLACE FUNCTION public.create_user_profile(
  p_user_id UUID,
  p_user_data JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_type TEXT;
  role TEXT;
  v_dob_text TEXT;
  v_dob TIMESTAMP WITH TIME ZONE;
BEGIN
  SELECT COALESCE(raw_user_meta_data->>'user_type', 'member') INTO user_type
  FROM auth.users
  WHERE id = p_user_id;

  role := CASE WHEN user_type = 'trusted_partner' THEN 'trusted_partner' ELSE 'member' END;

  v_dob_text := NULLIF(BTRIM(COALESCE(p_user_data->>'date_of_birth', '')), '');
  v_dob := NULL;

  IF v_dob_text IS NOT NULL THEN
    BEGIN
      IF v_dob_text ~ '^\d{4}-\d{2}-\d{2}$' THEN
        v_dob := (v_dob_text::date)::timestamp with time zone;
      ELSE
        v_dob := v_dob_text::timestamp with time zone;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        v_dob := NULL;
    END;
  END IF;

  INSERT INTO public.profiles (
    id,
    email,
    name,
    surname,
    date_of_birth,
    gender,
    ethnicity,
    province,
    street,
    suburb,
    city,
    contact,
    role,
    subscription
  )
  VALUES (
    p_user_id,
    NULLIF(BTRIM(COALESCE(p_user_data->>'email', '')), ''),
    NULLIF(BTRIM(COALESCE(p_user_data->>'name', '')), ''),
    NULLIF(BTRIM(COALESCE(p_user_data->>'surname', '')), ''),
    v_dob,
    NULLIF(BTRIM(COALESCE(p_user_data->>'gender', '')), ''),
    NULLIF(BTRIM(COALESCE(p_user_data->>'ethnicity', '')), ''),
    NULLIF(BTRIM(COALESCE(p_user_data->>'province', '')), ''),
    NULLIF(BTRIM(COALESCE(p_user_data->>'street', '')), ''),
    NULLIF(BTRIM(COALESCE(p_user_data->>'suburb', '')), ''),
    NULLIF(BTRIM(COALESCE(p_user_data->>'city', '')), ''),
    NULLIF(BTRIM(COALESCE(p_user_data->>'contact', '')), ''),
    role,
    CASE WHEN role = 'member' THEN 'pending' ELSE 'active' END
  )
  ON CONFLICT (id) DO UPDATE SET
    email = COALESCE(EXCLUDED.email, public.profiles.email),
    name = COALESCE(EXCLUDED.name, public.profiles.name),
    surname = COALESCE(EXCLUDED.surname, public.profiles.surname),
    date_of_birth = COALESCE(EXCLUDED.date_of_birth, public.profiles.date_of_birth),
    gender = COALESCE(EXCLUDED.gender, public.profiles.gender),
    ethnicity = COALESCE(EXCLUDED.ethnicity, public.profiles.ethnicity),
    province = COALESCE(EXCLUDED.province, public.profiles.province),
    street = COALESCE(EXCLUDED.street, public.profiles.street),
    suburb = COALESCE(EXCLUDED.suburb, public.profiles.suburb),
    city = COALESCE(EXCLUDED.city, public.profiles.city),
    contact = COALESCE(EXCLUDED.contact, public.profiles.contact),
    role = COALESCE(EXCLUDED.role, public.profiles.role),
    subscription = COALESCE(public.profiles.subscription, EXCLUDED.subscription),
    updated_at = NOW();

  INSERT INTO public.memberships (user_id, role, gateway)
  VALUES (p_user_id, role, 'user_signup')
  ON CONFLICT (user_id) DO UPDATE SET
    role = EXCLUDED.role,
    gateway = EXCLUDED.gateway,
    updated_at = NOW();

  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to create user profile: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_user_profile(UUID, JSONB) TO authenticated;
