-- Create RPC to allow admins to create trusted partners with a password
-- Uses direct auth.users insertion with bcrypt password hashing (works with custom Supabase setup)
-- Passes metadata for the trigger to create profiles/memberships/trusted_partners

CREATE OR REPLACE FUNCTION public.admin_create_trusted_partner(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  p_email text := lower(coalesce(payload->>'email',''));
  p_password text := coalesce(payload->>'password','');
  p_metadata jsonb := coalesce(payload->'metadata', '{}'::jsonb);
  p_business_name text := coalesce(payload->>'business_name','');
  v_user_id uuid := extensions.gen_random_uuid();
BEGIN
  IF p_email = '' OR p_password = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_email_or_password');
  END IF;

  -- Merge required flags into metadata to drive app/trigger behavior
  p_metadata := p_metadata
    || jsonb_build_object('user_type','trusted_partner')
    || jsonb_build_object('admin_created','true')
    || jsonb_build_object('password_set','true')
    || jsonb_build_object('email_verified','true')
    || jsonb_build_object('allow_admin_deal_creation','true');

  -- Create auth user by direct insertion with bcrypt password
  -- This is the working approach for this Supabase setup
  BEGIN
    INSERT INTO auth.users (
      id,
      email,
      encrypted_password,
      email_confirmed_at,
      confirmation_sent_at,
      confirmation_token,
      recovery_token,
      email_change,
      email_change_token_new,
      email_change_token_current,
      reauthentication_token,
      phone_change,
      phone_change_token,
      aud,
      role,
      instance_id,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    )
    VALUES (
      v_user_id,
      p_email,
      extensions.crypt(p_password, extensions.gen_salt('bf')),
      NOW(),
      NOW(),
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      'authenticated',
      'authenticated',
      '00000000-0000-0000-0000-000000000000',
      '{"provider":"email","providers":["email"]}'::jsonb,
      p_metadata,
      NOW(),
      NOW()
    )
    RETURNING id INTO v_user_id;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Failed to create auth user: ' || SQLERRM);
  END;

  -- Verify user was created
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'user_creation_failed_returned_null');
  END IF;

  RETURN jsonb_build_object('ok', true, 'user_id', v_user_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', 'RPC error: ' || SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_create_trusted_partner(jsonb) TO authenticated;
