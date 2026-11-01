-- =====================================================
-- FIX: Admin "Delete Member" leaves the member in the
-- Deactivated tab so they appear to come back.
--
-- Root cause:
--   Two SQL files defined public.admin_delete_member_data:
--     1) fix_admin_delete_member_hard_delete_auth.sql  (HARD delete)
--     2) update_admin_delete_member_with_archive.sql    (SOFT delete,
--        sets profiles.is_deactivated = true)
--
--   If (2) was applied after (1), the RPC only soft-deletes the
--   profile. The Flutter admin UI calls deleteMember(), the row is
--   removed from the Active/Pending tabs, but the same profile row
--   resurfaces under the Deactivated tab the next time the screen
--   loads -> the admin sees the "deleted" member listed again.
--
-- This script reinstalls the HARD-delete behaviour as the source of
-- truth and is safe to re-run.
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
  -- 1. Admin / service_role check
  caller_id := auth.uid();

  IF current_setting('role', true) = 'service_role' THEN
    is_admin := TRUE;
  ELSIF caller_id IS NOT NULL THEN
    SELECT TRUE INTO is_admin
      FROM public.profiles
     WHERE id = caller_id AND role = 'admin'
     LIMIT 1;

    IF NOT COALESCE(is_admin, FALSE) THEN
      SELECT TRUE INTO is_admin
        FROM public.memberships
       WHERE user_id = caller_id AND role = 'admin'
       LIMIT 1;
    END IF;

    IF NOT COALESCE(is_admin, FALSE) THEN
      IF EXISTS (
        SELECT 1 FROM information_schema.tables
         WHERE table_schema = 'public' AND table_name = 'admin_dashboard'
      ) THEN
        SELECT TRUE INTO is_admin
          FROM public.admin_dashboard
         WHERE admin_user_id = caller_id
         LIMIT 1;
      END IF;
    END IF;
  END IF;

  IF NOT COALESCE(is_admin, FALSE) THEN
    RAISE EXCEPTION 'Permission denied: caller is not an admin';
  END IF;

  -- 2. Capture identifying info (allow orphan auth cleanup too)
  SELECT email, name INTO member_email, member_name
    FROM public.profiles
   WHERE id = member_user_id AND role = 'member';

  IF NOT FOUND THEN
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

  -- 3. HARD delete dependent rows (guarded against missing tables/cols)

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

  -- chat_messages keyed by sender_id
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'chat_messages'
       AND column_name  = 'sender_id'
  ) THEN
    DELETE FROM public.chat_messages WHERE sender_id = member_user_id;
    result := result || jsonb_build_object('chat_messages_deleted', true);
  END IF;

  -- 4. HARD delete the profile (NOT a soft is_deactivated update)
  DELETE FROM public.profiles WHERE id = member_user_id;
  result := result || jsonb_build_object('profile_deleted', true);

  -- 5. HARD delete auth.users so the email can sign up fresh
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
