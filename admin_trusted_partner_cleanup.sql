-- Cleanup duplicate admin_create_trusted_partner definitions and recreate the canonical one
-- Run in Supabase SQL editor

-- Step 1a: Drop legacy overload (text, text, text)
DROP FUNCTION IF EXISTS public.admin_create_trusted_partner(text, text, text);

-- Step 1b: Drop all existing versions of the function (jsonb signature)
DO $$
DECLARE
  fn RECORD;
BEGIN
  FOR fn IN
    SELECT p.pronamespace, p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'admin_create_trusted_partner'
      AND pg_get_function_identity_arguments(p.oid) = 'payload jsonb'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS public.admin_create_trusted_partner(payload jsonb);');
  END LOOP;
END $$;

-- Step 2: Recreate the function with extensions-qualified pgcrypto
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
  v_user_id uuid;
BEGIN
  IF p_email = '' OR p_password = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_email_or_password');
  END IF;

  p_metadata := p_metadata
    || jsonb_build_object('user_type','trusted_partner')
    || jsonb_build_object('admin_created','true')
    || jsonb_build_object('password_set','true')
    || jsonb_build_object('email_verified','true');

  BEGIN
    INSERT INTO auth.users (email, encrypted_password, email_confirmed_at, raw_user_meta_data, created_at, updated_at)
    VALUES (
      p_email,
      extensions.crypt(p_password, extensions.gen_salt('bf')),
      NOW(),
      p_metadata,
      NOW(),
      NOW()
    )
    RETURNING id INTO v_user_id;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Failed to create auth user: ' || SQLERRM);
  END;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'user_creation_failed_returned_null');
  END IF;

  RETURN jsonb_build_object('ok', true, 'user_id', v_user_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', 'RPC error: ' || SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_create_trusted_partner(jsonb) TO authenticated;

-- Step 3: Verify only one function remains
SELECT
  p.oid,
  n.nspname AS schema,
  p.proname AS name,
  pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'admin_create_trusted_partner';
