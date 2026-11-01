-- =============================================================================
-- LOCAL LEKKER: LIVE DATABASE DIAGNOSTIC SCRIPT
-- Run this in the Supabase SQL Editor to compare your live DB against what
-- the Flutter app expects. Each section outputs results you can review.
-- =============================================================================
-- WARNING: This is READ-ONLY. No data is modified.
-- =============================================================================

-- =====================================================================
-- SECTION 1: CHECK ALL TABLES EXIST THAT THE APP EXPECTS
-- =====================================================================
-- The app code references these tables. Any missing = app crash.
SELECT 
  expected_table,
  CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = expected_table
  ) THEN '✅ EXISTS' ELSE '❌ MISSING' END AS status
FROM (VALUES
  ('profiles'),
  ('memberships'),
  ('subscriptions'),
  ('user_qr_codes'),
  ('trusted_partners'),
  ('businesses'),
  ('trusted_partner_discounts'),
  ('deal_authorizations'),
  ('notifications'),
  ('processed_bills'),
  ('payments'),
  ('trusted_partner_bank_accounts'),
  ('deal_receipts'),
  ('member_receipts'),
  ('virtual_receipts'),
  ('chat_conversations'),
  ('chat_messages'),
  ('members_card_details'),
  ('subscription_renewals'),
  ('members_bank_accounts'),
  ('recovery_sessions')
) AS t(expected_table)
ORDER BY status DESC, expected_table;

-- =====================================================================
-- SECTION 2: CHECK ALL COLUMNS THE APP REFERENCES EXIST
-- =====================================================================
-- Each row = one column the Flutter app queries/inserts/updates.
-- ❌ MISSING means the app will throw a Supabase error at runtime.
SELECT 
  expected_table,
  expected_column,
  CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = expected_table 
      AND column_name = expected_column
  ) THEN '✅ EXISTS' ELSE '❌ MISSING' END AS status
FROM (VALUES
  -- profiles (30 columns referenced by app)
  ('profiles', 'id'),
  ('profiles', 'email'),
  ('profiles', 'name'),
  ('profiles', 'surname'),
  ('profiles', 'role'),
  ('profiles', 'subscription'),
  ('profiles', 'is_deactivated'),
  ('profiles', 'deactivation_reason'),
  ('profiles', 'deactivated_at'),
  ('profiles', 'verified'),
  ('profiles', 'email_verified'),
  ('profiles', 'admin_created'),
  ('profiles', 'password_set'),
  ('profiles', 'date_of_birth'),
  ('profiles', 'gender'),
  ('profiles', 'ethnicity'),
  ('profiles', 'province'),
  ('profiles', 'street'),
  ('profiles', 'suburb'),
  ('profiles', 'city'),
  ('profiles', 'contact'),
  ('profiles', 'subscription_payment_method_id'),
  ('profiles', 'paystack_auth_code'),
  ('profiles', 'is_tp_member'),
  ('profiles', 'membership_role'),
  ('profiles', 'paystack_customer_code'),
  ('profiles', 'fcm_token'),
  ('profiles', 'paystack_subscription_code'),
  ('profiles', 'paystack_subaccount_code'),
  ('profiles', 'paystack_recipient_code'),
  ('profiles', 'in_app_password'),
  ('profiles', 'created_at'),
  ('profiles', 'updated_at'),

  -- subscriptions
  ('subscriptions', 'id'),
  ('subscriptions', 'user_id'),
  ('subscriptions', 'plan_type'),
  ('subscriptions', 'status'),
  ('subscriptions', 'current_period_start'),
  ('subscriptions', 'current_period_end'),
  ('subscriptions', 'paystack_subscription_code'),
  ('subscriptions', 'plan_name'),
  ('subscriptions', 'amount'),
  ('subscriptions', 'currency'),
  ('subscriptions', 'auto_renew'),
  ('subscriptions', 'created_at'),
  ('subscriptions', 'updated_at'),

  -- user_qr_codes
  ('user_qr_codes', 'id'),
  ('user_qr_codes', 'user_id'),
  ('user_qr_codes', 'qr_code'),
  ('user_qr_codes', 'name'),
  ('user_qr_codes', 'surname'),
  ('user_qr_codes', 'is_active'),
  ('user_qr_codes', 'expires_at'),
  ('user_qr_codes', 'created_at'),
  ('user_qr_codes', 'updated_at'),

  -- trusted_partner_discounts
  ('trusted_partner_discounts', 'id'),
  ('trusted_partner_discounts', 'name'),
  ('trusted_partner_discounts', 'trusted_partner_id'),
  ('trusted_partner_discounts', 'business_id'),
  ('trusted_partner_discounts', 'is_once_off'),
  ('trusted_partner_discounts', 'deal_type'),
  ('trusted_partner_discounts', 'custom_data'),
  ('trusted_partner_discounts', 'requires_manual_price'),
  ('trusted_partner_discounts', 'percentage'),
  ('trusted_partner_discounts', 'fixed_amount'),
  ('trusted_partner_discounts', 'item_price'),
  ('trusted_partner_discounts', 'item_name'),
  ('trusted_partner_discounts', 'is_active'),
  ('trusted_partner_discounts', 'city'),
  ('trusted_partner_discounts', 'created_at'),
  ('trusted_partner_discounts', 'description'),
  ('trusted_partner_discounts', 'image_url'),
  ('trusted_partner_discounts', 'is_weight_based'),
  ('trusted_partner_discounts', 'deal_category'),
  ('trusted_partner_discounts', 'schedule_data'),

  -- deal_authorizations
  ('deal_authorizations', 'id'),
  ('deal_authorizations', 'status'),
  ('deal_authorizations', 'member_id'),
  ('deal_authorizations', 'discount_id'),
  ('deal_authorizations', 'trusted_partner_id'),
  ('deal_authorizations', 'business_id'),
  ('deal_authorizations', 'amount'),
  ('deal_authorizations', 'payment_method'),
  ('deal_authorizations', 'payment_completed_at'),
  ('deal_authorizations', 'completed_at'),
  ('deal_authorizations', 'quantity'),
  ('deal_authorizations', 'deal_snapshot'),
  ('deal_authorizations', 'rejection_reason'),
  ('deal_authorizations', 'deal_type'),
  ('deal_authorizations', 'member_entered_price'),
  ('deal_authorizations', 'applied_discount_amount'),
  ('deal_authorizations', 'notes'),
  ('deal_authorizations', 'paid_at'),
  ('deal_authorizations', 'approved_at'),
  ('deal_authorizations', 'created_at'),
  ('deal_authorizations', 'updated_at'),
  ('deal_authorizations', 'is_once_off'),

  -- businesses
  ('businesses', 'id'),
  ('businesses', 'name'),
  ('businesses', 'owner_member_id'),
  ('businesses', 'category'),
  ('businesses', 'city'),
  ('businesses', 'logo_url'),
  ('businesses', 'receipt_counter'),
  ('businesses', 'created_at'),
  ('businesses', 'updated_at'),

  -- notifications
  ('notifications', 'id'),
  ('notifications', 'user_id'),
  ('notifications', 'is_read'),
  ('notifications', 'title'),
  ('notifications', 'message'),
  ('notifications', 'type'),
  ('notifications', 'data'),
  ('notifications', 'created_at'),

  -- processed_bills
  ('processed_bills', 'id'),
  ('processed_bills', 'status'),
  ('processed_bills', 'amount'),
  ('processed_bills', 'bill_data'),
  ('processed_bills', 'trusted_partner_id'),
  ('processed_bills', 'business_id'),
  ('processed_bills', 'member_id'),

  -- payments
  ('payments', 'id'),
  ('payments', 'user_id'),
  ('payments', 'amount'),
  ('payments', 'paystack_reference'),
  ('payments', 'status'),
  ('payments', 'completed_at'),
  ('payments', 'updated_at'),
  ('payments', 'raw_event'),

  -- trusted_partner_bank_accounts
  ('trusted_partner_bank_accounts', 'id'),
  ('trusted_partner_bank_accounts', 'user_id'),
  ('trusted_partner_bank_accounts', 'paystack_recipient_code'),
  ('trusted_partner_bank_accounts', 'account_type'),
  ('trusted_partner_bank_accounts', 'branch_code'),
  ('trusted_partner_bank_accounts', 'account_holder_name'),
  ('trusted_partner_bank_accounts', 'bank_name'),
  ('trusted_partner_bank_accounts', 'account_number'),
  ('trusted_partner_bank_accounts', 'is_active'),
  ('trusted_partner_bank_accounts', 'subaccount_code'),
  ('trusted_partner_bank_accounts', 'subaccount_active'),
  ('trusted_partner_bank_accounts', 'bank_account_type'),

  -- deal_receipts
  ('deal_receipts', 'id'),
  ('deal_receipts', 'deal_authorization_id'),
  ('deal_receipts', 'member_id'),
  ('deal_receipts', 'trusted_partner_id'),
  ('deal_receipts', 'business_id'),
  ('deal_receipts', 'receipt_number'),
  ('deal_receipts', 'amount'),
  ('deal_receipts', 'payment_method'),
  ('deal_receipts', 'transaction_date'),
  ('deal_receipts', 'status'),
  ('deal_receipts', 'business_name'),
  ('deal_receipts', 'member_name'),
  ('deal_receipts', 'member_email'),
  ('deal_receipts', 'discount_name'),

  -- virtual_receipts
  ('virtual_receipts', 'id'),
  ('virtual_receipts', 'deal_authorization_id'),
  ('virtual_receipts', 'receipt_number'),
  ('virtual_receipts', 'receipt_data'),
  ('virtual_receipts', 'qr_code'),

  -- chat_conversations
  ('chat_conversations', 'id'),
  ('chat_conversations', 'is_admin'),
  ('chat_conversations', 'created_at'),
  ('chat_conversations', 'participant_ids'),

  -- chat_messages
  ('chat_messages', 'id'),
  ('chat_messages', 'conversation_id'),
  ('chat_messages', 'sender_id'),
  ('chat_messages', 'content'),
  ('chat_messages', 'created_at'),
  ('chat_messages', 'read_by'),

  -- members_card_details
  ('members_card_details', 'id'),
  ('members_card_details', 'user_id'),
  ('members_card_details', 'authorization_code'),
  ('members_card_details', 'card_type'),
  ('members_card_details', 'last4'),
  ('members_card_details', 'exp_month'),
  ('members_card_details', 'exp_year'),
  ('members_card_details', 'bank'),
  ('members_card_details', 'brand'),
  ('members_card_details', 'is_primary'),
  ('members_card_details', 'is_active'),

  -- subscription_renewals
  ('subscription_renewals', 'id'),
  ('subscription_renewals', 'subscription_id'),
  ('subscription_renewals', 'user_id'),
  ('subscription_renewals', 'renewal_date'),
  ('subscription_renewals', 'amount'),
  ('subscription_renewals', 'status'),
  ('subscription_renewals', 'qr_code_updated'),

  -- memberships
  ('memberships', 'user_id'),
  ('memberships', 'role'),
  ('memberships', 'business_name'),

  -- trusted_partners
  ('trusted_partners', 'user_id'),
  ('trusted_partners', 'business_name'),
  ('trusted_partners', 'paystack_recipient_code'),
  ('trusted_partners', 'paystack_subaccount_code'),

  -- members_bank_accounts
  ('members_bank_accounts', 'id'),
  ('members_bank_accounts', 'user_id'),
  ('members_bank_accounts', 'paystack_recipient_code'),
  ('members_bank_accounts', 'account_type'),
  ('members_bank_accounts', 'branch_code'),
  ('members_bank_accounts', 'account_holder_name'),
  ('members_bank_accounts', 'bank_name'),
  ('members_bank_accounts', 'account_number'),
  ('members_bank_accounts', 'is_active'),

  -- recovery_sessions
  ('recovery_sessions', 'id'),
  ('recovery_sessions', 'user_id'),
  ('recovery_sessions', 'email'),
  ('recovery_sessions', 'token'),
  ('recovery_sessions', 'expires_at')

) AS t(expected_table, expected_column)
WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.columns 
  WHERE table_schema = 'public' 
    AND table_name = t.expected_table 
    AND column_name = t.expected_column
)
ORDER BY expected_table, expected_column;

-- =====================================================================
-- SECTION 3: CHECK RLS IS ENABLED ON ALL TABLES
-- =====================================================================
-- Every table the app uses MUST have RLS enabled, otherwise any
-- authenticated user can read/write all data.
SELECT 
  schemaname,
  tablename,
  CASE WHEN rowsecurity THEN '✅ RLS ON' ELSE '❌ RLS OFF - SECURITY RISK' END AS rls_status
FROM pg_tables 
WHERE schemaname = 'public'
  AND tablename IN (
    'profiles', 'memberships', 'subscriptions', 'user_qr_codes',
    'trusted_partners', 'businesses', 'trusted_partner_discounts',
    'deal_authorizations', 'notifications', 'processed_bills',
    'payments', 'trusted_partner_bank_accounts', 'deal_receipts',
    'member_receipts', 'virtual_receipts', 'chat_conversations',
    'chat_messages', 'members_card_details', 'subscription_renewals',
    'members_bank_accounts', 'recovery_sessions'
  )
ORDER BY rls_status, tablename;

-- =====================================================================
-- SECTION 4: CHECK ALL RLS POLICIES EXIST
-- =====================================================================
-- Lists all policies per table. Review carefully:
--   - Each table needs SELECT for the user's own rows
--   - INSERT policies for creating records
--   - UPDATE policies where needed
--   - Admin override policies
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles::text,
  cmd,
  LEFT(qual::text, 100) AS using_clause,
  LEFT(with_check::text, 100) AS with_check_clause
FROM pg_policies 
WHERE schemaname = 'public'
ORDER BY tablename, cmd, policyname;

-- =====================================================================
-- SECTION 5: CRITICAL RLS POLICY CHECKS
-- =====================================================================
-- These specific policies are REQUIRED by the app. Missing = broken flow.

-- 5a. notifications: INSERT must allow cross-user (TP creating notification for member)
SELECT 
  'notifications INSERT policy' AS check_name,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'notifications' 
      AND cmd = 'INSERT'
  ) THEN '✅ EXISTS' ELSE '❌ MISSING - TPs cannot notify members' END AS status;

-- 5b. deal_authorizations: Members need INSERT
SELECT 
  'deal_authorizations member INSERT' AS check_name,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'deal_authorizations' 
      AND cmd = 'INSERT'
  ) THEN '✅ EXISTS' ELSE '❌ MISSING - Members cannot request deals' END AS status;

-- 5c. deal_authorizations: TPs need UPDATE (to approve/reject)
SELECT 
  'deal_authorizations TP UPDATE' AS check_name,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'deal_authorizations' 
      AND cmd = 'UPDATE'
  ) THEN '✅ EXISTS' ELSE '❌ MISSING - TPs cannot approve deals' END AS status;

-- 5d. deal_authorizations: Members need SELECT on TP's deals too
SELECT 
  'deal_authorizations member SELECT' AS check_name,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'deal_authorizations' 
      AND cmd = 'SELECT'
  ) THEN '✅ EXISTS' ELSE '❌ MISSING - Cannot view deal status' END AS status;

-- 5e. trusted_partner_bank_accounts: Members need SELECT (for payment subaccount lookup)
SELECT 
  'trusted_partner_bank_accounts member SELECT' AS check_name,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'trusted_partner_bank_accounts' 
      AND cmd = 'SELECT'
      AND policyname ILIKE '%member%'
  ) THEN '✅ EXISTS' ELSE '⚠️ CHECK - Members may not be able to look up payment subaccounts' END AS status;

-- 5f. businesses: Public SELECT (all users can view businesses)
SELECT 
  'businesses public SELECT' AS check_name,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'businesses' 
      AND cmd = 'SELECT'
      AND qual::text ILIKE '%true%'
  ) THEN '✅ EXISTS (public)' ELSE '⚠️ CHECK - Businesses may not be publicly viewable' END AS status;

-- 5g. trusted_partner_discounts: Public SELECT for active deals
SELECT 
  'trusted_partner_discounts public SELECT' AS check_name,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'trusted_partner_discounts' 
      AND cmd = 'SELECT'
  ) THEN '✅ EXISTS' ELSE '❌ MISSING - Members cannot browse deals' END AS status;

-- 5h. deal_receipts: INSERT policy
SELECT 
  'deal_receipts INSERT' AS check_name,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'deal_receipts' 
      AND cmd = 'INSERT'
  ) THEN '✅ EXISTS' ELSE '❌ MISSING - Receipt generation will fail' END AS status;

-- 5i. virtual_receipts: INSERT policy
SELECT 
  'virtual_receipts INSERT' AS check_name,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'virtual_receipts' 
      AND cmd = 'INSERT'
  ) THEN '✅ EXISTS' ELSE '❌ MISSING - Virtual receipt generation will fail' END AS status;

-- 5j. members_card_details: Member INSERT/SELECT/UPDATE
SELECT 
  'members_card_details member operations' AS check_name,
  CASE WHEN (
    EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='members_card_details' AND cmd='SELECT')
    AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='members_card_details' AND cmd='INSERT')
    AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='members_card_details' AND cmd='UPDATE')
  ) THEN '✅ ALL EXIST' ELSE '❌ MISSING - Card save/load will fail' END AS status;

-- =====================================================================
-- SECTION 6: CHECK RPC FUNCTIONS EXIST
-- =====================================================================
-- The app calls these RPC functions. Missing = crash.
SELECT 
  expected_function,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = expected_function
  ) THEN '✅ EXISTS' ELSE '❌ MISSING' END AS status
FROM (VALUES
  ('get_my_role'),
  ('secure_get_admin_dashboard'),
  ('get_admin_dashboard'),
  ('prepare_user_context'),
  ('create_recovery_session'),
  ('create_notification_bypass_rls'),
  ('get_next_receipt_number'),
  ('is_deal_active_now'),
  ('generate_tp_unique_key'),
  ('admin_create_trusted_partner'),
  ('admin_delete_member_data'),
  ('admin_delete_trusted_partner'),
  ('complete_business_profile')
) AS t(expected_function)
ORDER BY status DESC, expected_function;

-- =====================================================================
-- SECTION 7: CHECK STORAGE BUCKETS EXIST
-- =====================================================================
SELECT 
  expected_bucket,
  CASE WHEN EXISTS (
    SELECT 1 FROM storage.buckets WHERE id = expected_bucket
  ) THEN '✅ EXISTS' ELSE '❌ MISSING' END AS status,
  (SELECT public FROM storage.buckets WHERE id = expected_bucket) AS is_public
FROM (VALUES
  ('business-bills'),
  ('receipt-images'),
  ('partner-logos'),
  ('deal-images')
) AS t(expected_bucket)
ORDER BY status DESC, expected_bucket;

-- =====================================================================
-- SECTION 8: CHECK STORAGE BUCKET RLS POLICIES
-- =====================================================================
SELECT 
  policyname AS policy_name,
  tablename,
  cmd AS operation,
  LEFT(qual::text, 120) AS using_clause,
  LEFT(with_check::text, 120) AS with_check_clause
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
ORDER BY policyname;

-- =====================================================================
-- SECTION 9: CHECK FOREIGN KEY RELATIONSHIPS
-- =====================================================================
-- Lists all foreign keys on the public schema tables
SELECT 
  tc.table_name AS source_table,
  kcu.column_name AS source_column,
  ccu.table_schema AS target_schema,
  ccu.table_name AS target_table,
  ccu.column_name AS target_column,
  rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu 
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu 
  ON tc.constraint_name = ccu.constraint_name
JOIN information_schema.referential_constraints rc
  ON tc.constraint_name = rc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY' 
  AND tc.table_schema = 'public'
ORDER BY tc.table_name, kcu.column_name;

-- =====================================================================
-- SECTION 10: CHECK REALTIME ENABLED
-- =====================================================================
-- The app uses Supabase Realtime for notifications
SELECT 
  t.relname AS table_name,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_publication_tables pt 
    WHERE pt.tablename = t.relname 
      AND pt.schemaname = 'public'
  ) THEN '✅ REALTIME ON' ELSE '⚠️ REALTIME OFF' END AS realtime_status
FROM pg_class t
JOIN pg_namespace n ON t.relnamespace = n.oid
WHERE n.nspname = 'public' 
  AND t.relkind = 'r'
  AND t.relname IN ('notifications', 'chat_messages', 'deal_authorizations')
ORDER BY t.relname;

-- =====================================================================
-- SECTION 11: CHECK WEBHOOK/TRIGGER FOR PUSH NOTIFICATIONS
-- =====================================================================
-- The app expects a database webhook on notifications INSERT that
-- calls the send-push-notification edge function
SELECT 
  trigger_name,
  event_manipulation,
  event_object_table,
  action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table IN ('notifications', 'deal_authorizations', 'subscriptions', 'profiles')
ORDER BY event_object_table, trigger_name;

-- =====================================================================
-- SECTION 12: FULL COLUMN LISTING FOR ALL APP TABLES
-- =====================================================================
-- Dump all actual columns so you can cross-reference visually
SELECT 
  table_name,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
    'profiles', 'memberships', 'subscriptions', 'user_qr_codes',
    'trusted_partners', 'businesses', 'trusted_partner_discounts',
    'deal_authorizations', 'notifications', 'processed_bills',
    'payments', 'trusted_partner_bank_accounts', 'deal_receipts',
    'member_receipts', 'virtual_receipts', 'chat_conversations',
    'chat_messages', 'members_card_details', 'subscription_renewals',
    'members_bank_accounts', 'recovery_sessions'
  )
ORDER BY table_name, ordinal_position;

-- =====================================================================
-- SECTION 13: CHECK FOR ORPHANED/EXTRA TABLES
-- =====================================================================
-- Tables in the DB that the app doesn't reference (may be leftovers)
SELECT table_name AS potentially_unused_table
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
  AND table_name NOT IN (
    'profiles', 'memberships', 'subscriptions', 'user_qr_codes',
    'trusted_partners', 'businesses', 'trusted_partner_discounts',
    'deal_authorizations', 'notifications', 'processed_bills',
    'payments', 'trusted_partner_bank_accounts', 'deal_receipts',
    'member_receipts', 'virtual_receipts', 'chat_conversations',
    'chat_messages', 'members_card_details', 'subscription_renewals',
    'members_bank_accounts', 'recovery_sessions',
    'archived_members', 'archived_receipts', 'archived_paystack_data',
    'archived_pending_payments', 'bill_approvals', 'calibration_receipts',
    'admin_dashboard'
  )
ORDER BY table_name;

-- =====================================================================
-- SECTION 14: CHECK deal_authorizations TRUSTED_PARTNER_ID REFERENCES
-- =====================================================================
-- The comprehensive_schema references businesses(id) but the app may
-- use the TP's user_id directly. Check what the FK actually points to.
SELECT
  kcu.column_name,
  ccu.table_name AS references_table,
  ccu.column_name AS references_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu 
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu 
  ON tc.constraint_name = ccu.constraint_name
WHERE tc.table_name = 'deal_authorizations'
  AND tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
ORDER BY kcu.column_name;

-- =====================================================================
-- DONE! Review the output of each section above.
-- Look for ❌ MISSING items - those are the critical issues.
-- ⚠️ items should be reviewed but may not be blocking.
-- =====================================================================
