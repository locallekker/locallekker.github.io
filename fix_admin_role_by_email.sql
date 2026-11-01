-- =====================================================================
-- FIX ADMIN ROLE BY EMAIL (robust against UUID mismatch)
-- =====================================================================
-- Problem: create_admin_user.sql hard-codes a fixed UUID
-- (985fa2aa-45c7-450a-a8b8-ff63934a6193). If the real auth account has a
-- different UUID, the 'admin' rows are orphaned and the logged-in admin
-- resolves to role 'member' -> gets asked to pay.
--
-- This script resolves the REAL user id from auth.users by email and writes
-- role='admin' into profiles + memberships, and sets user metadata
-- user_type='admin'. Run it in the Supabase SQL Editor (service role).
-- =====================================================================

DO $$
DECLARE
  v_email   text := 'locallekkerclub@gmail.com';  -- <-- change if needed
  v_user_id uuid;
BEGIN
  -- 1. Resolve the ACTUAL auth user id from the email
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE lower(email) = lower(v_email)
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No auth.users row found for email %, create the auth user first', v_email;
  END IF;

  RAISE NOTICE 'Resolved admin user id: %', v_user_id;

  -- 2. Upsert profiles.role = 'admin'
  INSERT INTO public.profiles (id, email, name, surname, role, created_at, updated_at)
  VALUES (v_user_id, v_email, 'Local Lekker', 'Admin', 'admin', now(), now())
  ON CONFLICT (id) DO UPDATE SET
    role = 'admin',
    updated_at = now();

  -- 3. Upsert memberships.role = 'admin'
  INSERT INTO public.memberships (user_id, role, gateway, created_at, updated_at)
  VALUES (v_user_id, 'admin', 'manual', now(), now())
  ON CONFLICT (user_id) DO UPDATE SET
    role = 'admin',
    updated_at = now();

  -- 4. Set auth metadata user_type='admin' so the client fast-path also works
  UPDATE auth.users
  SET raw_user_meta_data =
        COALESCE(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('user_type', 'admin')
  WHERE id = v_user_id;

  RAISE NOTICE 'Admin role applied for % (%).', v_email, v_user_id;
END $$;

-- =====================================================================
-- VERIFICATION
-- =====================================================================
SELECT u.id,
       u.email,
       u.raw_user_meta_data ->> 'user_type' AS metadata_user_type,
       p.role  AS profiles_role,
       m.role  AS memberships_role
FROM auth.users u
LEFT JOIN public.profiles    p ON p.id      = u.id
LEFT JOIN public.memberships m ON m.user_id = u.id
WHERE lower(u.email) = lower('locallekkerclub@gmail.com');

-- Confirm the SECURITY DEFINER role RPC returns 'admin' for this user.
-- (Run while authenticated as the admin, or trust the columns above.)
-- SELECT public.get_my_role();
