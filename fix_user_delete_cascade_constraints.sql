-- =============================================================================
-- FIX: Add ON DELETE CASCADE to auth.users foreign key constraints
-- Problem: Supabase Auth dashboard cannot delete users because the profiles,
--          memberships, and trusted_partners tables reference auth.users without
--          ON DELETE CASCADE, blocking deletion.
-- 
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor).
-- It is safe to run multiple times (idempotent).
-- =============================================================================

BEGIN;

-- -------------------------------------------------------------------------
-- 1. FIX: profiles.id -> auth.users (PRIMARY KEY, needs CASCADE)
-- -------------------------------------------------------------------------
DO $$
DECLARE
  v_constraint TEXT;
BEGIN
  SELECT conname INTO v_constraint
  FROM pg_constraint
  WHERE conrelid = 'public.profiles'::regclass
    AND confrelid = 'auth.users'::regclass
    AND contype = 'f';

  IF v_constraint IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.profiles DROP CONSTRAINT %I', v_constraint);
    RAISE NOTICE 'Dropped constraint % from profiles', v_constraint;
  END IF;
END $$;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_id_fkey
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- -------------------------------------------------------------------------
-- 2. FIX: memberships.user_id -> auth.users (PRIMARY KEY, needs CASCADE)
-- -------------------------------------------------------------------------
DO $$
DECLARE
  v_constraint TEXT;
BEGIN
  SELECT conname INTO v_constraint
  FROM pg_constraint
  WHERE conrelid = 'public.memberships'::regclass
    AND confrelid = 'auth.users'::regclass
    AND contype = 'f';

  IF v_constraint IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.memberships DROP CONSTRAINT %I', v_constraint);
    RAISE NOTICE 'Dropped constraint % from memberships', v_constraint;
  END IF;
END $$;

ALTER TABLE public.memberships
  ADD CONSTRAINT memberships_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- -------------------------------------------------------------------------
-- 3. FIX: trusted_partners.user_id -> auth.users (PRIMARY KEY, needs CASCADE)
-- -------------------------------------------------------------------------
DO $$
DECLARE
  v_constraint TEXT;
BEGIN
  SELECT conname INTO v_constraint
  FROM pg_constraint
  WHERE conrelid = 'public.trusted_partners'::regclass
    AND confrelid = 'auth.users'::regclass
    AND contype = 'f';

  IF v_constraint IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.trusted_partners DROP CONSTRAINT %I', v_constraint);
    RAISE NOTICE 'Dropped constraint % from trusted_partners', v_constraint;
  END IF;
END $$;

ALTER TABLE public.trusted_partners
  ADD CONSTRAINT trusted_partners_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- -------------------------------------------------------------------------
-- 4. FIX: processed_bills.approved_by -> auth.users (nullable, SET NULL)
-- -------------------------------------------------------------------------
DO $$
DECLARE
  v_constraint TEXT;
BEGIN
  SELECT conname INTO v_constraint
  FROM pg_constraint c
  JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
  WHERE c.conrelid = 'public.processed_bills'::regclass
    AND c.confrelid = 'auth.users'::regclass
    AND c.contype = 'f'
    AND a.attname = 'approved_by';

  IF v_constraint IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.processed_bills DROP CONSTRAINT %I', v_constraint);
    RAISE NOTICE 'Dropped approved_by constraint % from processed_bills', v_constraint;
  END IF;
END $$;

-- Only add if the column exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'processed_bills'
      AND column_name = 'approved_by'
  ) THEN
    ALTER TABLE public.processed_bills
      ADD CONSTRAINT processed_bills_approved_by_fkey
      FOREIGN KEY (approved_by) REFERENCES auth.users(id) ON DELETE SET NULL;
    RAISE NOTICE 'Added SET NULL constraint for processed_bills.approved_by';
  END IF;
END $$;

-- -------------------------------------------------------------------------
-- 5. FIX: processed_bills.trusted_partner_id -> auth.users (SET NULL)
-- -------------------------------------------------------------------------
DO $$
DECLARE
  v_constraint TEXT;
BEGIN
  SELECT conname INTO v_constraint
  FROM pg_constraint c
  JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
  WHERE c.conrelid = 'public.processed_bills'::regclass
    AND c.confrelid = 'auth.users'::regclass
    AND c.contype = 'f'
    AND a.attname = 'trusted_partner_id';

  IF v_constraint IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.processed_bills DROP CONSTRAINT %I', v_constraint);
    RAISE NOTICE 'Dropped trusted_partner_id constraint % from processed_bills', v_constraint;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'processed_bills'
      AND column_name = 'trusted_partner_id'
  ) THEN
    ALTER TABLE public.processed_bills
      ADD CONSTRAINT processed_bills_trusted_partner_id_fkey
      FOREIGN KEY (trusted_partner_id) REFERENCES auth.users(id) ON DELETE SET NULL;
    RAISE NOTICE 'Added SET NULL constraint for processed_bills.trusted_partner_id';
  END IF;
END $$;

-- -------------------------------------------------------------------------
-- 6. FIX: archived_members.deleted_by -> auth.users (nullable admin ref, SET NULL)
-- -------------------------------------------------------------------------
DO $$
DECLARE
  v_constraint TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'archived_members'
  ) THEN RETURN; END IF;

  SELECT conname INTO v_constraint
  FROM pg_constraint c
  JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
  WHERE c.conrelid = 'public.archived_members'::regclass
    AND c.confrelid = 'auth.users'::regclass
    AND c.contype = 'f'
    AND a.attname = 'deleted_by';

  IF v_constraint IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.archived_members DROP CONSTRAINT %I', v_constraint);
    RAISE NOTICE 'Dropped deleted_by constraint % from archived_members', v_constraint;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'archived_members' AND column_name = 'deleted_by'
  ) THEN
    ALTER TABLE public.archived_members
      ADD CONSTRAINT archived_members_deleted_by_fkey
      FOREIGN KEY (deleted_by) REFERENCES auth.users(id) ON DELETE SET NULL;
    RAISE NOTICE 'Added SET NULL constraint for archived_members.deleted_by';
  END IF;
END $$;

-- -------------------------------------------------------------------------
-- 7. FIX: bill_approvals.partner_id -> auth.users
--    Column is NOT NULL so SET NULL would fail. Drop NOT NULL first, then SET NULL.
-- -------------------------------------------------------------------------
DO $$
DECLARE
  v_constraint TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'bill_approvals'
  ) THEN RETURN; END IF;

  -- Drop the NOT NULL constraint so SET NULL can work
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'bill_approvals'
      AND column_name = 'partner_id' AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE public.bill_approvals ALTER COLUMN partner_id DROP NOT NULL;
    RAISE NOTICE 'Dropped NOT NULL from bill_approvals.partner_id';
  END IF;

  -- Drop the existing FK (which had NO ACTION or old SET NULL)
  SELECT conname INTO v_constraint
  FROM pg_constraint c
  JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
  WHERE c.conrelid = 'public.bill_approvals'::regclass
    AND c.confrelid = 'auth.users'::regclass
    AND c.contype = 'f'
    AND a.attname = 'partner_id';

  IF v_constraint IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.bill_approvals DROP CONSTRAINT %I', v_constraint);
    RAISE NOTICE 'Dropped partner_id constraint % from bill_approvals', v_constraint;
  END IF;

  -- Re-add with SET NULL (now that column is nullable)
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'bill_approvals' AND column_name = 'partner_id'
  ) THEN
    ALTER TABLE public.bill_approvals
      ADD CONSTRAINT bill_approvals_partner_id_fkey
      FOREIGN KEY (partner_id) REFERENCES auth.users(id) ON DELETE SET NULL;
    RAISE NOTICE 'Added SET NULL constraint for bill_approvals.partner_id';
  END IF;
END $$;

-- -------------------------------------------------------------------------
-- 8. FIX: processed_bills.partner_id -> auth.users (nullable partner ref, SET NULL)
-- -------------------------------------------------------------------------
DO $$
DECLARE
  v_constraint TEXT;
BEGIN
  SELECT conname INTO v_constraint
  FROM pg_constraint c
  JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
  WHERE c.conrelid = 'public.processed_bills'::regclass
    AND c.confrelid = 'auth.users'::regclass
    AND c.contype = 'f'
    AND a.attname = 'partner_id';

  IF v_constraint IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.processed_bills DROP CONSTRAINT %I', v_constraint);
    RAISE NOTICE 'Dropped partner_id constraint % from processed_bills', v_constraint;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'processed_bills' AND column_name = 'partner_id'
  ) THEN
    ALTER TABLE public.processed_bills
      ADD CONSTRAINT processed_bills_partner_id_fkey
      FOREIGN KEY (partner_id) REFERENCES auth.users(id) ON DELETE SET NULL;
    RAISE NOTICE 'Added SET NULL constraint for processed_bills.partner_id';
  END IF;
END $$;

-- -------------------------------------------------------------------------
-- VERIFY: List all remaining auth.users FK constraints (should all have CASCADE or SET NULL)
-- -------------------------------------------------------------------------
SELECT
  tc.table_name,
  kcu.column_name,
  rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.referential_constraints rc
  ON tc.constraint_name = rc.constraint_name
JOIN information_schema.key_column_usage ccu
  ON rc.unique_constraint_name = ccu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
  AND ccu.table_schema = 'auth'
  AND ccu.table_name = 'users'
ORDER BY tc.table_name, kcu.column_name;

-- =============================================================================
-- PHASE 2: Fix FK constraints on tables that reference profiles(id)
-- When auth.users is deleted → profiles is cascade-deleted → but tables that
-- reference profiles(id) WITHOUT CASCADE block the profile deletion.
-- =============================================================================

-- -------------------------------------------------------------------------
-- DIAGNOSTIC: Show all FKs pointing at profiles(id) with their delete rule
-- (Run this first to see what's blocking)
-- -------------------------------------------------------------------------
SELECT
  tc.table_name,
  kcu.column_name,
  rc.delete_rule,
  tc.constraint_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
JOIN information_schema.referential_constraints rc
  ON tc.constraint_name = rc.constraint_name
JOIN information_schema.key_column_usage ccu
  ON rc.unique_constraint_name = ccu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
  AND ccu.table_schema = 'public'
  AND ccu.table_name = 'profiles'
ORDER BY rc.delete_rule, tc.table_name, kcu.column_name;

-- -------------------------------------------------------------------------
-- Helper: Generic function to fix a FK on profiles(id)
-- pass delete_action = 'CASCADE' or 'SET NULL'
-- If the column is NOT NULL and action is SET NULL, drops NOT NULL first.
-- -------------------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
  v_action TEXT;
  v_col_nullable TEXT;
BEGIN
  FOR r IN
    SELECT
      tc.table_name,
      kcu.column_name,
      tc.constraint_name,
      rc.delete_rule
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    JOIN information_schema.referential_constraints rc
      ON tc.constraint_name = rc.constraint_name
    JOIN information_schema.key_column_usage ccu
      ON rc.unique_constraint_name = ccu.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema = 'public'
      AND ccu.table_schema = 'public'
      AND ccu.table_name = 'profiles'
      AND rc.delete_rule = 'NO ACTION'   -- only fix broken ones
    ORDER BY tc.table_name, kcu.column_name
  LOOP
    -- Ownership/identity columns → CASCADE
    -- Audit/reference columns → SET NULL
    IF r.column_name IN ('user_id', 'member_id', 'trusted_partner_id', 'partner_id') THEN
      v_action := 'CASCADE';
    ELSE
      v_action := 'SET NULL';
    END IF;

    -- If SET NULL but column is NOT NULL, drop the NOT NULL first
    IF v_action = 'SET NULL' THEN
      SELECT is_nullable INTO v_col_nullable
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = r.table_name
        AND column_name = r.column_name;

      IF v_col_nullable = 'NO' THEN
        EXECUTE format('ALTER TABLE public.%I ALTER COLUMN %I DROP NOT NULL', r.table_name, r.column_name);
        RAISE NOTICE 'Dropped NOT NULL from %.%', r.table_name, r.column_name;
      END IF;
    END IF;

    -- Drop old constraint
    EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', r.table_name, r.constraint_name);
    RAISE NOTICE 'Dropped FK % (was NO ACTION)', r.constraint_name;

    -- Re-add with correct delete rule
    EXECUTE format(
      'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES public.profiles(id) ON DELETE %s',
      r.table_name, r.constraint_name, r.column_name, v_action
    );
    RAISE NOTICE 'Re-added FK % with ON DELETE %', r.constraint_name, v_action;
  END LOOP;
END $$;

-- -------------------------------------------------------------------------
-- VERIFY Phase 2: All profiles(id) FKs should now be CASCADE or SET NULL
-- -------------------------------------------------------------------------
SELECT
  tc.table_name,
  kcu.column_name,
  rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
JOIN information_schema.referential_constraints rc
  ON tc.constraint_name = rc.constraint_name
JOIN information_schema.key_column_usage ccu
  ON rc.unique_constraint_name = ccu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
  AND ccu.table_schema = 'public'
  AND ccu.table_name = 'profiles'
ORDER BY tc.table_name, kcu.column_name;

-- =============================================================================
-- PHASE 3: Fix ALL remaining NO ACTION FKs across the entire public schema
-- Covers: businesses, trusted_partner_discounts, deal_authorizations,
--         virtual_receipts, and any other tables in the cascade chain.
-- =============================================================================
DO $$
DECLARE
  r RECORD;
  v_action TEXT;
  v_col_nullable TEXT;
BEGIN
  FOR r IN
    SELECT
      tc.table_schema,
      tc.table_name,
      kcu.column_name,
      tc.constraint_name,
      ccu.table_name AS ref_table,
      ccu.column_name AS ref_column
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    JOIN information_schema.referential_constraints rc
      ON tc.constraint_name = rc.constraint_name
    JOIN information_schema.key_column_usage ccu
      ON rc.unique_constraint_name = ccu.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema = 'public'
      AND rc.delete_rule = 'NO ACTION'
    ORDER BY tc.table_name, kcu.column_name
  LOOP
    -- Ownership/dependency columns → CASCADE
    -- Audit/soft-reference columns → SET NULL
    IF r.column_name IN (
      'id', 'user_id', 'member_id', 'trusted_partner_id', 'partner_id',
      'business_id', 'deal_authorization_id', 'discount_id', 'bill_id',
      'subscription_id', 'receipt_id', 'payment_id'
    ) THEN
      v_action := 'CASCADE';
    ELSE
      -- Audit / reference columns (created_by, used_by, confirmed_by, etc.)
      v_action := 'SET NULL';
    END IF;

    -- For SET NULL: drop NOT NULL if needed
    IF v_action = 'SET NULL' THEN
      SELECT is_nullable INTO v_col_nullable
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = r.table_name
        AND column_name = r.column_name;

      IF v_col_nullable = 'NO' THEN
        EXECUTE format(
          'ALTER TABLE public.%I ALTER COLUMN %I DROP NOT NULL',
          r.table_name, r.column_name
        );
        RAISE NOTICE 'Dropped NOT NULL from %.%', r.table_name, r.column_name;
      END IF;
    END IF;

    -- Drop the old NO ACTION constraint
    EXECUTE format(
      'ALTER TABLE public.%I DROP CONSTRAINT %I',
      r.table_name, r.constraint_name
    );
    RAISE NOTICE 'Dropped NO ACTION FK % on %.%', r.constraint_name, r.table_name, r.column_name;

    -- Re-add with correct delete rule, referencing the original table/column
    EXECUTE format(
      'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES public.%I(%I) ON DELETE %s',
      r.table_name, r.constraint_name, r.column_name,
      r.ref_table, r.ref_column, v_action
    );
    RAISE NOTICE 'Re-added FK % → %.% ON DELETE %', r.constraint_name, r.ref_table, r.ref_column, v_action;
  END LOOP;

  RAISE NOTICE 'Phase 3 complete.';
END $$;

-- -------------------------------------------------------------------------
-- FINAL VERIFY: No NO ACTION FKs should remain anywhere in public schema
-- -------------------------------------------------------------------------
SELECT
  tc.table_name,
  kcu.column_name,
  ccu.table_name AS references_table,
  rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
JOIN information_schema.referential_constraints rc
  ON tc.constraint_name = rc.constraint_name
JOIN information_schema.key_column_usage ccu
  ON rc.unique_constraint_name = ccu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
  AND rc.delete_rule = 'NO ACTION'
ORDER BY tc.table_name, kcu.column_name;

-- (Empty result = all FKs are now CASCADE or SET NULL)

-- =============================================================================
-- PHASE 4: Drop the redundant delete_user_cascade trigger on auth.users
-- This trigger manually deletes rows that CASCADE now handles automatically.
-- If it references a renamed/missing table it throws and rolls back the deletion.
-- Safe to remove — all cleanup is covered by ON DELETE CASCADE constraints.
-- =============================================================================
DROP TRIGGER IF EXISTS on_auth_user_deleted ON auth.users;

-- Verify it's gone (should return 0 rows)
SELECT tgname, tgrelid::regclass AS table_name
FROM pg_trigger
WHERE tgrelid = 'auth.users'::regclass
  AND tgname = 'on_auth_user_deleted';

COMMIT;
