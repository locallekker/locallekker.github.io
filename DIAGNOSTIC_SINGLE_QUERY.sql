-- =============================================================================
-- LOCAL LEKKER: CONSOLIDATED DIAGNOSTIC (Single Result Set)
-- Paste this ENTIRE script into Supabase SQL Editor and run.
-- All results appear in ONE table. Look for ❌ MISSING items.
-- =============================================================================

WITH table_checks AS (
  SELECT 
    '1-TABLE' AS section,
    expected_table AS item,
    '' AS detail,
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.tables 
      WHERE table_schema = 'public' AND table_name = expected_table
    ) THEN '✅ EXISTS' ELSE '❌ MISSING' END AS status
  FROM (VALUES
    ('profiles'), ('memberships'), ('subscriptions'), ('user_qr_codes'),
    ('trusted_partners'), ('businesses'), ('trusted_partner_discounts'),
    ('deal_authorizations'), ('notifications'), ('processed_bills'),
    ('payments'), ('trusted_partner_bank_accounts'), ('deal_receipts'),
    ('member_receipts'), ('virtual_receipts'), ('chat_conversations'),
    ('chat_messages'), ('members_card_details'), ('subscription_renewals'),
    ('members_bank_accounts'), ('recovery_sessions')
  ) AS t(expected_table)
),

column_checks AS (
  SELECT 
    '2-COLUMN' AS section,
    expected_table AS item,
    expected_column AS detail,
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
        AND table_name = expected_table 
        AND column_name = expected_column
    ) THEN '✅ EXISTS' ELSE '❌ MISSING' END AS status
  FROM (VALUES
    ('profiles','id'), ('profiles','email'), ('profiles','name'), ('profiles','surname'),
    ('profiles','role'), ('profiles','subscription'), ('profiles','is_deactivated'),
    ('profiles','deactivation_reason'), ('profiles','deactivated_at'), ('profiles','verified'),
    ('profiles','email_verified'), ('profiles','admin_created'), ('profiles','password_set'),
    ('profiles','date_of_birth'), ('profiles','gender'), ('profiles','ethnicity'),
    ('profiles','province'), ('profiles','street'), ('profiles','suburb'), ('profiles','city'),
    ('profiles','contact'), ('profiles','subscription_payment_method_id'),
    ('profiles','paystack_auth_code'), ('profiles','is_tp_member'),
    ('profiles','paystack_customer_code'), ('profiles','fcm_token'),
    ('profiles','created_at'), ('profiles','updated_at'),
    -- NOTE: membership_role lives in memberships.role (code fixed)
    -- NOTE: paystack_subscription_code lives in subscriptions table
    -- NOTE: paystack_subaccount_code lives in trusted_partners table
    -- NOTE: paystack_recipient_code lives in trusted_partner_bank_accounts table
    -- NOTE: in_app_password deprecated in favor of Supabase auth

    ('subscriptions','id'), ('subscriptions','user_id'), ('subscriptions','plan_type'),
    ('subscriptions','status'), ('subscriptions','current_period_start'),
    ('subscriptions','current_period_end'), ('subscriptions','paystack_subscription_code'),
    ('subscriptions','plan_name'), ('subscriptions','amount'), ('subscriptions','currency'),
    ('subscriptions','auto_renew'), ('subscriptions','created_at'), ('subscriptions','updated_at'),

    ('user_qr_codes','id'), ('user_qr_codes','user_id'), ('user_qr_codes','qr_code'),
    ('user_qr_codes','name'), ('user_qr_codes','surname'), ('user_qr_codes','is_active'),
    ('user_qr_codes','expires_at'), ('user_qr_codes','created_at'), ('user_qr_codes','updated_at'),

    ('trusted_partner_discounts','id'), ('trusted_partner_discounts','name'),
    ('trusted_partner_discounts','trusted_partner_id'), ('trusted_partner_discounts','business_id'),
    ('trusted_partner_discounts','is_once_off'), ('trusted_partner_discounts','deal_type'),
    ('trusted_partner_discounts','custom_data'), ('trusted_partner_discounts','requires_manual_price'),
    ('trusted_partner_discounts','percentage'), ('trusted_partner_discounts','fixed_amount'),
    ('trusted_partner_discounts','item_price'), ('trusted_partner_discounts','item_name'),
    ('trusted_partner_discounts','is_active'), ('trusted_partner_discounts','city'),
    ('trusted_partner_discounts','created_at'), ('trusted_partner_discounts','description'),
    ('trusted_partner_discounts','image_url'), ('trusted_partner_discounts','is_weight_based'),
    ('trusted_partner_discounts','deal_category'), ('trusted_partner_discounts','schedule_data'),

    ('deal_authorizations','id'), ('deal_authorizations','status'),
    ('deal_authorizations','member_id'), ('deal_authorizations','discount_id'),
    ('deal_authorizations','trusted_partner_id'), ('deal_authorizations','business_id'),
    ('deal_authorizations','amount'), ('deal_authorizations','payment_method'),
    ('deal_authorizations','payment_completed_at'), ('deal_authorizations','completed_at'),
    ('deal_authorizations','quantity'), ('deal_authorizations','deal_snapshot'),
    ('deal_authorizations','rejection_reason'), ('deal_authorizations','deal_type'),
    ('deal_authorizations','member_entered_price'), ('deal_authorizations','applied_discount_amount'),
    ('deal_authorizations','notes'),
    ('deal_authorizations','approved_at'), ('deal_authorizations','created_at'),
    ('deal_authorizations','updated_at'), ('deal_authorizations','is_once_off'),
    -- NOTE: paid_at not used in app code, status tracking uses deal_authorizations.status

    ('businesses','id'), ('businesses','name'), ('businesses','owner_member_id'),
    ('businesses','category'), ('businesses','city'), ('businesses','logo_url'),
    ('businesses','receipt_counter'), ('businesses','created_at'), ('businesses','updated_at'),

    ('notifications','id'), ('notifications','user_id'), ('notifications','is_read'),
    ('notifications','title'), ('notifications','message'), ('notifications','type'),
    ('notifications','data'), ('notifications','created_at'),

    ('processed_bills','id'), ('processed_bills','status'), ('processed_bills','amount'),
    ('processed_bills','bill_data'), ('processed_bills','trusted_partner_id'),
    ('processed_bills','business_id'), ('processed_bills','member_id'),

    ('payments','id'), ('payments','user_id'), ('payments','amount'),
    ('payments','paystack_reference'), ('payments','status'), ('payments','completed_at'),
    ('payments','updated_at'), ('payments','raw_event'),

    ('trusted_partner_bank_accounts','id'), ('trusted_partner_bank_accounts','user_id'),
    ('trusted_partner_bank_accounts','paystack_recipient_code'),
    ('trusted_partner_bank_accounts','account_type'), ('trusted_partner_bank_accounts','branch_code'),
    ('trusted_partner_bank_accounts','account_holder_name'), ('trusted_partner_bank_accounts','bank_name'),
    ('trusted_partner_bank_accounts','account_number'), ('trusted_partner_bank_accounts','is_active'),
    ('trusted_partner_bank_accounts','subaccount_code'), ('trusted_partner_bank_accounts','subaccount_active'),
    ('trusted_partner_bank_accounts','bank_account_type'),

    ('deal_receipts','id'), ('deal_receipts','deal_authorization_id'),
    ('deal_receipts','member_id'), ('deal_receipts','trusted_partner_id'),
    ('deal_receipts','business_id'), ('deal_receipts','receipt_number'),
    ('deal_receipts','amount'), ('deal_receipts','payment_method'),
    ('deal_receipts','business_name'), ('deal_receipts','member_name'),
    -- NOTE: transaction_date and status live in virtual_receipts.receipt_data JSON, not as columns
    ('deal_receipts','member_email'), ('deal_receipts','discount_name'),

    ('virtual_receipts','id'), ('virtual_receipts','deal_authorization_id'),
    ('virtual_receipts','receipt_number'), ('virtual_receipts','receipt_data'),
    ('virtual_receipts','qr_code'),

    ('chat_conversations','id'), ('chat_conversations','is_admin'),
    ('chat_conversations','created_at'), ('chat_conversations','participant_ids'),

    ('chat_messages','id'), ('chat_messages','conversation_id'),
    ('chat_messages','sender_id'), ('chat_messages','content'),
    ('chat_messages','created_at'), ('chat_messages','read_by'),

    ('members_card_details','id'), ('members_card_details','user_id'),
    ('members_card_details','authorization_code'), ('members_card_details','card_type'),
    ('members_card_details','last4'), ('members_card_details','exp_month'),
    ('members_card_details','exp_year'), ('members_card_details','bank'),
    ('members_card_details','brand'), ('members_card_details','is_primary'),
    ('members_card_details','is_active'),

    ('subscription_renewals','id'), ('subscription_renewals','subscription_id'),
    ('subscription_renewals','user_id'), ('subscription_renewals','renewal_date'),
    ('subscription_renewals','amount'), ('subscription_renewals','status'),
    ('subscription_renewals','qr_code_updated'),

    ('memberships','user_id'), ('memberships','role'),
    -- NOTE: business_name lives on businesses and trusted_partners tables, not memberships

    ('trusted_partners','user_id'), ('trusted_partners','business_name'),
    ('trusted_partners','paystack_recipient_code'), ('trusted_partners','paystack_subaccount_code'),

    ('members_bank_accounts','id'), ('members_bank_accounts','user_id'),
    ('members_bank_accounts','paystack_recipient_code'), ('members_bank_accounts','account_type'),
    ('members_bank_accounts','branch_code'), ('members_bank_accounts','account_holder_name'),
    ('members_bank_accounts','bank_name'), ('members_bank_accounts','account_number'),
    ('members_bank_accounts','is_active'),

    ('recovery_sessions','id'), ('recovery_sessions','user_id'),
    ('recovery_sessions','email'), ('recovery_sessions','token'),
    ('recovery_sessions','expires_at')
  ) AS t(expected_table, expected_column)
),

rls_checks AS (
  SELECT 
    '3-RLS' AS section,
    tablename AS item,
    '' AS detail,
    CASE WHEN rowsecurity THEN '✅ RLS ON' ELSE '❌ RLS OFF - SECURITY RISK' END AS status
  FROM pg_tables 
  WHERE schemaname = 'public'
    AND tablename IN (
      'profiles','memberships','subscriptions','user_qr_codes',
      'trusted_partners','businesses','trusted_partner_discounts',
      'deal_authorizations','notifications','processed_bills',
      'payments','trusted_partner_bank_accounts','deal_receipts',
      'member_receipts','virtual_receipts','chat_conversations',
      'chat_messages','members_card_details','subscription_renewals',
      'members_bank_accounts','recovery_sessions'
    )
),

policy_checks AS (
  SELECT '4-POLICY' AS section, 'notifications' AS item, 'INSERT' AS detail,
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='notifications' AND cmd='INSERT')
    THEN '✅ EXISTS' ELSE '❌ MISSING - TPs cannot notify members' END AS status
  UNION ALL
  SELECT '4-POLICY', 'deal_authorizations', 'INSERT',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='deal_authorizations' AND cmd='INSERT')
    THEN '✅ EXISTS' ELSE '❌ MISSING - Members cannot request deals' END
  UNION ALL
  SELECT '4-POLICY', 'deal_authorizations', 'UPDATE',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='deal_authorizations' AND cmd='UPDATE')
    THEN '✅ EXISTS' ELSE '❌ MISSING - TPs cannot approve deals' END
  UNION ALL
  SELECT '4-POLICY', 'deal_authorizations', 'SELECT',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='deal_authorizations' AND cmd='SELECT')
    THEN '✅ EXISTS' ELSE '❌ MISSING - Cannot view deal status' END
  UNION ALL
  SELECT '4-POLICY', 'deal_authorizations', 'DELETE',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='deal_authorizations' AND cmd='DELETE')
    THEN '✅ EXISTS' ELSE '❌ MISSING - Cannot delete deals' END
  UNION ALL
  SELECT '4-POLICY', 'trusted_partner_bank_accounts', 'member SELECT',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='trusted_partner_bank_accounts' AND cmd='SELECT' AND policyname ILIKE '%member%')
    THEN '✅ EXISTS' ELSE '⚠️ CHECK - Members may not lookup subaccounts' END
  UNION ALL
  SELECT '4-POLICY', 'businesses', 'public SELECT',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='businesses' AND cmd='SELECT' AND qual::text ILIKE '%true%')
    THEN '✅ EXISTS' ELSE '⚠️ CHECK - May not be publicly viewable' END
  UNION ALL
  SELECT '4-POLICY', 'trusted_partner_discounts', 'SELECT',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='trusted_partner_discounts' AND cmd='SELECT')
    THEN '✅ EXISTS' ELSE '❌ MISSING - Cannot browse deals' END
  UNION ALL
  SELECT '4-POLICY', 'deal_receipts', 'INSERT',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='deal_receipts' AND cmd='INSERT')
    THEN '✅ EXISTS' ELSE '❌ MISSING - Receipt generation will fail' END
  UNION ALL
  SELECT '4-POLICY', 'virtual_receipts', 'INSERT',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='virtual_receipts' AND cmd='INSERT')
    THEN '✅ EXISTS' ELSE '❌ MISSING - Virtual receipt will fail' END
  UNION ALL
  SELECT '4-POLICY', 'members_card_details', 'SELECT+INSERT+UPDATE',
    CASE WHEN (
      EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='members_card_details' AND cmd='SELECT')
      AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='members_card_details' AND cmd='INSERT')
      AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='members_card_details' AND cmd='UPDATE')
    ) THEN '✅ ALL EXIST' ELSE '❌ MISSING - Card save/load will fail' END
  UNION ALL
  SELECT '4-POLICY', 'subscriptions', 'INSERT',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='subscriptions' AND cmd='INSERT')
    THEN '✅ EXISTS' ELSE '❌ MISSING - Subscription creation fails' END
  UNION ALL
  SELECT '4-POLICY', 'subscriptions', 'DELETE',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='subscriptions' AND cmd='DELETE')
    THEN '✅ EXISTS' ELSE '⚠️ CHECK - Subscription cleanup may fail' END
  UNION ALL
  SELECT '4-POLICY', 'user_qr_codes', 'INSERT',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_qr_codes' AND cmd='INSERT')
    THEN '✅ EXISTS' ELSE '❌ MISSING - QR code creation fails' END
  UNION ALL
  SELECT '4-POLICY', 'user_qr_codes', 'UPDATE',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_qr_codes' AND cmd='UPDATE')
    THEN '✅ EXISTS' ELSE '⚠️ CHECK - QR code deactivation may fail' END
  UNION ALL
  SELECT '4-POLICY', 'profiles', 'INSERT',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND cmd='INSERT')
    THEN '✅ EXISTS' ELSE '❌ MISSING - Profile creation fails' END
  UNION ALL
  SELECT '4-POLICY', 'profiles', 'UPDATE',
    CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND cmd='UPDATE')
    THEN '✅ EXISTS' ELSE '❌ MISSING - Profile updates fail' END
),

function_checks AS (
  SELECT 
    '5-RPC' AS section,
    expected_function AS item,
    '' AS detail,
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'public' AND p.proname = expected_function
    ) THEN '✅ EXISTS' ELSE '❌ MISSING' END AS status
  FROM (VALUES
    ('get_my_role'), ('secure_get_admin_dashboard'), ('get_admin_dashboard'),
    ('prepare_user_context'), ('create_recovery_session'),
    ('create_notification_bypass_rls'), ('get_next_receipt_number'),
    ('is_deal_active_now'), ('generate_tp_unique_key'),
    ('admin_create_trusted_partner'), ('admin_delete_member_data'),
    ('admin_delete_trusted_partner'), ('complete_business_profile')
  ) AS t(expected_function)
),

bucket_checks AS (
  SELECT 
    '6-BUCKET' AS section,
    expected_bucket AS item,
    COALESCE((SELECT CASE WHEN public THEN 'public' ELSE 'private' END FROM storage.buckets WHERE id = expected_bucket), 'N/A') AS detail,
    CASE WHEN EXISTS (SELECT 1 FROM storage.buckets WHERE id = expected_bucket)
    THEN '✅ EXISTS' ELSE '❌ MISSING' END AS status
  FROM (VALUES
    ('business-bills'), ('receipt-images'), ('partner-logos'), ('deal-images')
  ) AS t(expected_bucket)
),

realtime_checks AS (
  SELECT 
    '7-REALTIME' AS section,
    t.relname AS item,
    '' AS detail,
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_publication_tables pt 
      WHERE pt.tablename = t.relname AND pt.schemaname = 'public'
    ) THEN '✅ REALTIME ON' ELSE '⚠️ REALTIME OFF' END AS status
  FROM pg_class t
  JOIN pg_namespace n ON t.relnamespace = n.oid
  WHERE n.nspname = 'public' AND t.relkind = 'r'
    AND t.relname IN ('notifications', 'chat_messages', 'deal_authorizations')
)

-- FINAL OUTPUT: Everything in one result set
SELECT section, item, detail, status FROM table_checks WHERE status LIKE '❌%'
UNION ALL
SELECT section, item, detail, status FROM column_checks WHERE status LIKE '❌%'
UNION ALL
SELECT section, item, detail, status FROM rls_checks
UNION ALL
SELECT section, item, detail, status FROM policy_checks
UNION ALL
SELECT section, item, detail, status FROM function_checks
UNION ALL
SELECT section, item, detail, status FROM bucket_checks
UNION ALL
SELECT section, item, detail, status FROM realtime_checks
ORDER BY section, status DESC, item, detail;
