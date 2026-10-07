-- Restore the RPC used by the admin trusted-partner screen.
-- The function must validate the caller before inserting into auth.users.

CREATE OR REPLACE FUNCTION public.admin_create_trusted_partner(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  p_email text := lower(trim(coalesce(payload->>'email', '')));
  p_password text := coalesce(payload->>'password', '');
  p_metadata jsonb := coalesce(payload->'metadata', '{}'::jsonb);
  p_business_name text := coalesce(p_metadata->>'business_name', '');
  p_category text := coalesce(p_metadata->>'category', '');
  p_city text := coalesce(p_metadata->>'city', '');
  p_contact text := coalesce(p_metadata->>'contact', '');
  v_user_id uuid := extensions.gen_random_uuid();
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.memberships
    WHERE user_id = auth.uid()
      AND role = 'admin'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'admin_access_required');
  END IF;

  IF p_email = '' OR p_password = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_email_or_password');
  END IF;

  p_metadata := p_metadata
    || jsonb_build_object('user_type', 'trusted_partner')
    || jsonb_build_object('admin_created', true)
    || jsonb_build_object('password_set', true)
    || jsonb_build_object('email_verified', true)
    || jsonb_build_object('allow_admin_deal_creation', true);

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
    );
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Failed to create auth user: ' || SQLERRM);
  END;

  IF p_business_name <> '' THEN
    BEGIN
      INSERT INTO public.businesses (
        owner_member_id,
        name,
        category,
        city,
        contact_number,
        contact_email,
        allow_admin_deal_creation,
        created_at,
        updated_at
      )
      VALUES (
        v_user_id,
        p_business_name,
        NULLIF(p_category, ''),
        NULLIF(p_city, ''),
        NULLIF(p_contact, ''),
        p_email,
        true,
        NOW(),
        NOW()
      )
      ON CONFLICT DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Failed to create business for TP %: %', v_user_id, SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object('ok', true, 'user_id', v_user_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', 'RPC error: ' || SQLERRM);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_trusted_partner(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_trusted_partner(jsonb) TO authenticated;
