-- =============================================================================
-- APPLY SEARCH_PATH FIXES TO ALL AFFECTED FUNCTIONS
-- =============================================================================
-- This script adds SET search_path = public to all 19 functions flagged by
-- Security Advisor as missing the search_path parameter.
--
-- Run this entire file in Supabase SQL Editor to fix all warnings at once.
-- =============================================================================
-- Note: Using dynamic ALTER statements to avoid parameter mismatch errors
-- =============================================================================

DO $$
DECLARE
    func_record RECORD;
    fix_sql TEXT;
    fixed_count INTEGER := 0;
    failed_count INTEGER := 0;
BEGIN
    -- List of functions to fix
    FOR func_record IN 
        SELECT 
            n.nspname as schema_name,
            p.proname as function_name,
            pg_get_function_identity_arguments(p.oid) as args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.prokind = 'f'
          AND p.proname IN (
            'accept_partner_terms',
            'admin_delete_user',
            'check_email_exists',
            'create_notification_bypass_rls',
            'create_profile_from_auth',
            'delete_user_cascade',
            'generate_tp_unique_key',
            'get_admin_analytics',
            'get_admin_dashboard',
            'get_all_deal_authorizations',
            'get_monthly_revenue_breakdown',
            'get_next_receipt_number',
            'get_top_deals',
            'get_top_members',
            'set_tp_unique_key',
            'update_business_logos_updated_at',
            'update_deal_receipts_updated_at',
            'update_merchant_discounts_updated_at',
            'update_payments_updated_at'
          )
          AND pg_get_functiondef(p.oid) NOT LIKE '%SET search_path%'
    LOOP
        -- Generate ALTER FUNCTION statement with correct signature
        fix_sql := format('ALTER FUNCTION %I.%I(%s) SET search_path = public;',
                         func_record.schema_name,
                         func_record.function_name,
                         func_record.args);
        
        BEGIN
            EXECUTE fix_sql;
            fixed_count := fixed_count + 1;
            RAISE NOTICE '✅ Fixed: %.%(%)', 
                func_record.schema_name, 
                func_record.function_name,
                func_record.args;
        EXCEPTION WHEN OTHERS THEN
            failed_count := failed_count + 1;
            RAISE WARNING '❌ Failed to fix %.%(%): %', 
                func_record.schema_name,
                func_record.function_name,
                func_record.args,
                SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE '';
    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'Summary: Fixed % functions, Failed %', fixed_count, failed_count;
    RAISE NOTICE '=============================================================================';
END $$;

-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Verify all functions now have search_path set:
SELECT 
    p.proname as function_name,
    CASE 
        WHEN pg_get_functiondef(p.oid) LIKE '%SET search_path%' THEN '✅ FIXED'
        ELSE '❌ STILL MISSING'
    END as status
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND p.proname IN (
    'accept_partner_terms',
    'admin_delete_user',
    'check_email_exists',
    'create_notification_bypass_rls',
    'create_profile_from_auth',
    'delete_user_cascade',
    'generate_tp_unique_key',
    'get_admin_analytics',
    'get_admin_dashboard',
    'get_all_deal_authorizations',
    'get_monthly_revenue_breakdown',
    'get_next_receipt_number',
    'get_top_deals',
    'get_top_members',
    'set_tp_unique_key',
    'update_business_logos_updated_at',
    'update_deal_receipts_updated_at',
    'update_merchant_discounts_updated_at',
    'update_payments_updated_at'
  )
ORDER BY p.proname;

-- Expected result: All 19 functions should show "✅ FIXED"
