-- Create a SECURITY DEFINER function to handle profile creation
-- This bypasses RLS policies and can be called by authenticated users

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
  profile_data JSONB;
BEGIN
  -- Get user type from metadata (this function runs with elevated privileges)
  SELECT COALESCE(raw_user_meta_data->>'user_type', 'member') INTO user_type
  FROM auth.users
  WHERE id = p_user_id;

  -- Determine role
  role := CASE WHEN user_type = 'trusted_partner' THEN 'trusted_partner' ELSE 'member' END;

  -- Build profile data
  profile_data := jsonb_build_object(
    'id', p_user_id,
    'email', p_user_data->>'email',
    'name', p_user_data->>'name',
    'surname', p_user_data->>'surname',
    'date_of_birth', CASE WHEN p_user_data->>'date_of_birth' IS NOT NULL THEN to_timestamp(p_user_data->>'date_of_birth', 'YYYY-MM-DD"T"HH24:MI:SS.MS') ELSE NULL END,
    'gender', p_user_data->>'gender',
    'ethnicity', p_user_data->>'ethnicity',
    'province', p_user_data->>'province',
    'street', p_user_data->>'street',
    'suburb', p_user_data->>'suburb',
    'city', p_user_data->>'city',
    'contact', p_user_data->>'contact',
    'role', role,
    'subscription', CASE WHEN role = 'member' THEN 'pending' ELSE 'active' END
  );

  -- Remove null values
  profile_data := profile_data - (SELECT array_agg(k) FROM jsonb_object_keys(profile_data) k WHERE profile_data->k IS NULL);

  -- Upsert profile
  INSERT INTO public.profiles SELECT * FROM jsonb_to_record(profile_data) AS x(
    id UUID, email TEXT, name TEXT, surname TEXT, date_of_birth TIMESTAMP WITH TIME ZONE,
    gender TEXT, ethnicity TEXT, province TEXT, street TEXT, suburb TEXT,
    city TEXT, contact TEXT, role TEXT, subscription TEXT
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    name = EXCLUDED.name,
    surname = EXCLUDED.surname,
    date_of_birth = EXCLUDED.date_of_birth,
    gender = EXCLUDED.gender,
    ethnicity = EXCLUDED.ethnicity,
    province = EXCLUDED.province,
    street = EXCLUDED.street,
    suburb = EXCLUDED.suburb,
    city = EXCLUDED.city,
    contact = EXCLUDED.contact,
    role = EXCLUDED.role,
    subscription = EXCLUDED.subscription;

  -- Create membership record
  INSERT INTO public.memberships (user_id, role, gateway)
  VALUES (p_user_id, role, 'user_signup')
  ON CONFLICT (user_id) DO UPDATE SET
    role = EXCLUDED.role,
    gateway = EXCLUDED.gateway;

  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to create user profile: %', SQLERRM;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.create_user_profile(UUID, JSONB) TO authenticated;