-- =====================================================
-- FIX: admin_delete_member_data must HARD DELETE the auth.users row
-- =====================================================
-- Problem:
--   The previously deployed version of admin_delete_member_data
--   (deploy_member_archive_system.sql) only marked the profile as
--   "is_deactivated = true" and never removed the row from auth.users.
--   As a result, when the deleted member tried to sign up again with
--   the same email, Supabase Auth saw an existing auth.users row and
--   sent a password-recovery / magic-link email instead of a fresh
--   signup OTP.
--
-- Fix:
--   Restore hard-delete behaviour for everything that belongs to the
--   member, including the auth.users row. Because this function is
--   SECURITY DEFINER and runs as the database owner (postgres), it is
--   allowed to DELETE FROM auth.users directly. This makes the cleanup
--   reliable even if the delete-auth-user Edge Function is not
--   deployed or fails to run.
--
-- Run this in Supabase SQL Editor.
-- =====================================================

CREATE OR REPLACE FUNCTION public.admin_delete_member_data(member_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result        JSONB;
  member_email  TEXT;
  member_name   TEXT;
  caller_id     UUID;
  is_admin      BOOLEAN := FALSE;
  tbl_name      TEXT;
  sql           TEXT;
BEGIN
  -- ---------------------------------------------------------------
  -- 1. Verify caller is an admin (defence-in-depth on top of RLS /
  --    edge function checks). Allow service_role automatically.
  -- ---------------------------------------------------------------
  caller_id := auth.uid();

  IF current_setting('role', true) = 'service_role' THEN
    is_admin := TRUE;
  ELSIF caller_id IS NOT NULL THEN
    SELECT TRUE
      INTO is_admin
      FROM public.profiles
     WHERE id = caller_id
       AND role = 'admin'
     LIMIT 1;

    IF NOT COALESCE(is_admin, FALSE) THEN
      SELECT TRUE
        INTO is_admin
        FROM public.memberships
       WHERE user_id = caller_id
         AND role = 'admin'
       LIMIT 1;
    END IF;

    IF NOT COALESCE(is_admin, FALSE) THEN
      IF EXISTS (
        SELECT 1 FROM information_schema.tables
         WHERE table_schema = 'public' AND table_name = 'admin_dashboard'
      ) THEN
        SELECT TRUE
          INTO is_admin
          FROM public.admin_dashboard
         WHERE admin_user_id = caller_id
         LIMIT 1;
      END IF;
    END IF;
  END IF;

  IF NOT COALESCE(is_admin, FALSE) THEN
    RAISE EXCEPTION 'Permission denied: caller is not an admin';
  END IF;

  -- ---------------------------------------------------------------
  -- 2. Verify target user is a member and capture identifying info
  -- ---------------------------------------------------------------
  SELECT email, name
    INTO member_email, member_name
    FROM public.profiles
   WHERE id = member_user_id
     AND role = 'member';

  IF NOT FOUND THEN
    -- Still allow deletion if the profile is missing but the auth row
    -- exists (orphan cleanup). Pull the email from auth.users.
    SELECT email INTO member_email FROM auth.users WHERE id = member_user_id;
    IF member_email IS NULL THEN
      RAISE EXCEPTION 'User % does not exist or is not a member', member_user_id;
    END IF;
  END IF;

  result := jsonb_build_object(
    'member_id', member_user_id,
    'email',     member_email,
    'name',      member_name,
    'action',    'hard_deleted'
  );

  -- ---------------------------------------------------------------
  -- 3. Hard-delete all member-related rows in dependency-safe order.
  --    Each block is guarded so missing tables/columns do not abort.
  -- ---------------------------------------------------------------

  -- Tables keyed by member_id
  FOREACH tbl_name IN ARRAY ARRAY[
    'member_receipts',
    'deal_authorizations',
    'processed_bills'
  ] LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name   = tbl_name
         AND column_name  = 'member_id'
    ) THEN
      sql := format('DELETE FROM public.%I WHERE member_id = $1', tbl_name);
      EXECUTE sql USING member_user_id;
      result := result || jsonb_build_object(tbl_name || '_deleted', true);
    END IF;
  END LOOP;

  -- Tables keyed by user_id
  FOREACH tbl_name IN ARRAY ARRAY[
    'chat_read_receipts',
    'members_card_details',
    'user_qr_codes',
    'subscription_renewals',
    'subscriptions',
    'payments',
    'notifications',
    'memberships'
  ] LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name   = tbl_name
         AND column_name  = 'user_id'
    ) THEN
      sql := format('DELETE FROM public.%I WHERE user_id = $1', tbl_name);
      EXECUTE sql USING member_user_id;
      result := result || jsonb_build_object(tbl_name || '_deleted', true);
    END IF;
  END LOOP;

  -- Chat messages keyed by sender_id
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'chat_messages'
       AND column_name  = 'sender_id'
  ) THEN
    DELETE FROM public.chat_messages WHERE sender_id = member_user_id;
    result := result || jsonb_build_object('chat_messages_deleted', true);
  END IF;

  -- Profile (must be removed before auth.users when there is an FK)
  DELETE FROM public.profiles WHERE id = member_user_id;
  result := result || jsonb_build_object('profile_deleted', true);

  -- ---------------------------------------------------------------
  -- 4. Finally, hard-delete the auth.users row so the email becomes
  --    available for a fresh signup (and Supabase will send an OTP
  --    rather than a recovery email).
  -- ---------------------------------------------------------------
  DELETE FROM auth.users WHERE id = member_user_id;
  result := result || jsonb_build_object('auth_user_deleted', true);

  RETURN result::json;

EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to delete member %: %', member_user_id, SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_member_data(UUID) TO authenticated;

-- Backward-compatible wrapper
CREATE OR REPLACE FUNCTION public.admin_delete_member(member_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.admin_delete_member_data(member_user_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_member(UUID) TO authenticated;

-- =====================================================
-- Verification queries (run manually after deploy):
--
--   SELECT pg_get_functiondef('public.admin_delete_member_data'::regproc);
--
--   -- After deleting a member from the admin UI, confirm:
--   SELECT id, email FROM auth.users WHERE id = '<member_uuid>';
--   -- => should return zero rows
-- =====================================================
