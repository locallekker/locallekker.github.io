-- =====================================================
-- FIX: admin_delete_member_data must HARD DELETE the member
-- across ALL tables, including ones not in the hardcoded list.
-- =====================================================
-- Problem:
--   Previous versions of admin_delete_member_data only cleaned up a
--   fixed list of tables (member_receipts, subscriptions, payments,
--   notifications, memberships, etc.). The schema has grown to include
--   many more tables with FK references to public.profiles(id) or
--   auth.users(id), e.g.:
--     - admin_promo_keys (used_by, created_by)
--     - tp_member_keys (used_by, created_by, trusted_partner_id)
--     - intro_campaign_promotions / promo_claims
--     - deal_receipts (member_id, trusted_partner_id)
--     - recovery_sessions
--     - calibration_receipts
--     - archived_members (deleted_by)
--     - promotions (user_id)
--     - ... and any new tables added later
--
--   If ANY of these has a row pointing at the member, the final
--   DELETE FROM public.profiles or DELETE FROM auth.users raises a
--   FK violation. The EXCEPTION WHEN OTHERS block re-raises and the
--   whole transaction rolls back -> the admin sees "Failed to delete"
--   (or worse: a silent partial state) and the member is NOT removed.
--
-- Fix:
--   Discover all FK constraints referencing public.profiles(id) and
--   auth.users(id) at runtime via pg_catalog, then for each referring
--   column either DELETE the rows (if NOT NULL) or SET NULL (if
--   nullable). This is self-maintaining: any future tables that add
--   FKs to profiles/auth.users are cleaned up automatically.
--
-- Safe to re-run.
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
  fk_rec        RECORD;
  fk_sql        TEXT;
  cleaned_count INT := 0;
  cleaned_tables JSONB := '[]'::jsonb;
BEGIN
  -- ---------------------------------------------------------------
  -- 1. Verify caller is an admin (service_role auto-allowed).
  -- ---------------------------------------------------------------
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

  -- ---------------------------------------------------------------
  -- 2. Capture identifying info (allow orphan auth cleanup too).
  -- ---------------------------------------------------------------
  SELECT email, name INTO member_email, member_name
    FROM public.profiles
   WHERE id = member_user_id;

  IF NOT FOUND THEN
    SELECT email INTO member_email FROM auth.users WHERE id = member_user_id;
    IF member_email IS NULL THEN
      RAISE EXCEPTION 'User % does not exist in profiles or auth.users', member_user_id;
    END IF;
  END IF;

  result := jsonb_build_object(
    'member_id', member_user_id,
    'email',     member_email,
    'name',      member_name,
    'action',    'hard_deleted'
  );

  -- ---------------------------------------------------------------
  -- 3. Discover and clean up EVERY foreign key in any schema that
  --    references either public.profiles(id) or auth.users(id).
  --    For each referring column:
  --      - if the column is NOT NULL -> DELETE the row
  --      - if the column is NULLable -> UPDATE ... SET col = NULL
  --    This keeps audit columns like created_by / used_by intact for
  --    historical rows while removing rows that genuinely belong to
  --    the member (subscriptions, payments, qr codes, etc.).
  --
  --    The profiles row itself is skipped here and deleted explicitly
  --    in step 4, and auth.users in step 5.
  -- ---------------------------------------------------------------
  FOR fk_rec IN
    SELECT
      n.nspname        AS schema_name,
      c.relname        AS table_name,
      a.attname        AS column_name,
      a.attnotnull     AS not_null,
      rn.nspname       AS ref_schema,
      rc.relname       AS ref_table
    FROM pg_constraint con
    JOIN pg_class      c   ON c.oid  = con.conrelid
    JOIN pg_namespace  n   ON n.oid  = c.relnamespace
    JOIN pg_class      rc  ON rc.oid = con.confrelid
    JOIN pg_namespace  rn  ON rn.oid = rc.relnamespace
    JOIN pg_attribute  a   ON a.attrelid = con.conrelid
                          AND a.attnum  = ANY (con.conkey)
    JOIN pg_attribute  ra  ON ra.attrelid = con.confrelid
                          AND ra.attnum  = ANY (con.confkey)
    WHERE con.contype = 'f'
      AND (
            (rn.nspname = 'public' AND rc.relname = 'profiles' AND ra.attname = 'id')
         OR (rn.nspname = 'auth'   AND rc.relname = 'users'    AND ra.attname = 'id')
          )
      -- Skip the target tables themselves; handled below.
      AND NOT (n.nspname = 'public' AND c.relname = 'profiles')
      AND NOT (n.nspname = 'auth'   AND c.relname = 'users')
      -- Skip system / supabase-managed tables we must not touch.
      AND n.nspname NOT IN ('pg_catalog', 'information_schema',
                            'auth', 'storage', 'realtime',
                            'supabase_functions', 'extensions',
                            'graphql', 'graphql_public', 'vault',
                            'pgsodium', 'pgsodium_masks', 'net')
  LOOP
    BEGIN
      IF fk_rec.not_null THEN
        fk_sql := format(
          'DELETE FROM %I.%I WHERE %I = $1',
          fk_rec.schema_name, fk_rec.table_name, fk_rec.column_name
        );
      ELSE
        fk_sql := format(
          'UPDATE %I.%I SET %I = NULL WHERE %I = $1',
          fk_rec.schema_name, fk_rec.table_name,
          fk_rec.column_name, fk_rec.column_name
        );
      END IF;

      EXECUTE fk_sql USING member_user_id;
      GET DIAGNOSTICS cleaned_count = ROW_COUNT;

      IF cleaned_count > 0 THEN
        cleaned_tables := cleaned_tables || jsonb_build_object(
          'table',  fk_rec.schema_name || '.' || fk_rec.table_name,
          'column', fk_rec.column_name,
          'op',     CASE WHEN fk_rec.not_null THEN 'delete' ELSE 'set_null' END,
          'rows',   cleaned_count
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Don't let one stubborn table abort the whole delete.
      -- Record it and continue; the final profile/auth delete will
      -- surface any remaining FK issue clearly.
      cleaned_tables := cleaned_tables || jsonb_build_object(
        'table',  fk_rec.schema_name || '.' || fk_rec.table_name,
        'column', fk_rec.column_name,
        'error',  SQLERRM
      );
    END;
  END LOOP;

  result := result || jsonb_build_object('cleaned', cleaned_tables);

  -- ---------------------------------------------------------------
  -- 4. Hard-delete the profile row itself.
  -- ---------------------------------------------------------------
  DELETE FROM public.profiles WHERE id = member_user_id;
  result := result || jsonb_build_object('profile_deleted', true);

  -- ---------------------------------------------------------------
  -- 5. Hard-delete the auth.users row so the email frees up and
  --    Supabase sends a fresh signup OTP next time.
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

-- Backward-compatible wrapper used by older callers.
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
-- Verification:
--
--   -- 1. Confirm the updated function is installed:
--   SELECT pg_get_functiondef('public.admin_delete_member_data'::regproc);
--
--   -- 2. After deleting a member from the admin UI:
--   SELECT id FROM public.profiles WHERE id = '<member_uuid>'; -- 0 rows
--   SELECT id FROM auth.users     WHERE id = '<member_uuid>'; -- 0 rows
--
--   -- 3. Inspect what was cleaned (returned in JSON result.cleaned[]).
-- =====================================================
