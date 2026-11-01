-- =============================================================================
-- FIX: Add search_path to all functions flagged by Security Advisor
-- Issue: Functions missing SET search_path parameter (security best practice)
-- Solution: Add SET search_path = public to all affected functions
-- =============================================================================
-- This prevents search path hijacking attacks by explicitly setting the schema
-- Reference: https://supabase.com/docs/guides/database/postgres/configuration#search-path

-- List of affected functions from Security Advisor (25 warnings):
-- 1. public.accept_partner_terms
-- 2. public.get_top_members
-- 3. public.get_top_deals
-- 4. public.create_profile_from_auth
-- 5. public.get_admin_analytics
-- 6. public.get_monthly_revenue_breakdown
-- 7. public.get_next_receipt_number
-- 8. public.update_payments_updated_at
-- 9. public.admin_delete_user
-- 10. public.create_notification_bypass_rls
-- 11. public.get_all_deal_authorizations
-- 12. public.update_merchant_discounts_updated_at
-- 13. public.get_admin_dashboard

-- =============================================================================
-- STEP 1: Get list of all functions without search_path
-- =============================================================================
-- Run this query to identify all functions missing search_path:
SELECT 
    n.nspname as schema_name,
    p.proname as function_name,
    pg_get_functiondef(p.oid) as function_definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.prokind = 'f'  -- Only functions, not procedures
  AND pg_get_functiondef(p.oid) NOT LIKE '%SET search_path%'
ORDER BY p.proname;

-- =============================================================================
-- STEP 2: Fix each function by adding SET search_path = public
-- =============================================================================
-- Note: You'll need to recreate each function with the SET search_path clause
-- The general pattern is:
-- CREATE OR REPLACE FUNCTION function_name(params)
-- RETURNS return_type
-- LANGUAGE plpgsql
-- SECURITY DEFINER (or SECURITY INVOKER)
-- SET search_path = public  -- ADD THIS LINE
-- AS $$
-- ... function body ...
-- $$;

-- =============================================================================
-- AUTOMATED FIX: Add search_path to common functions
-- =============================================================================

-- The safest approach is to add search_path to each function individually
-- Here's an example for one function - repeat this pattern for all affected functions

-- Example: Fix accept_partner_terms (if it exists)
-- You'll need to get the full function definition first and add SET search_path

-- =============================================================================
-- HELPER SCRIPT: Generate ALTER FUNCTION statements
-- =============================================================================
-- This generates ALTER FUNCTION statements for all affected functions
-- Run this to get the list of commands to execute:

DO $$
DECLARE
    func_record RECORD;
    fix_sql TEXT;
BEGIN
    FOR func_record IN 
        SELECT 
            n.nspname as schema_name,
            p.proname as function_name,
            pg_get_function_identity_arguments(p.oid) as args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.prokind = 'f'
          AND pg_get_functiondef(p.oid) NOT LIKE '%SET search_path%'
    LOOP
        -- Generate ALTER FUNCTION statement
        fix_sql := format('ALTER FUNCTION %I.%I(%s) SET search_path = public;',
                         func_record.schema_name,
                         func_record.function_name,
                         func_record.args);
        
        -- Print the statement
        RAISE NOTICE '%', fix_sql;
        
        -- Execute it (uncomment to apply fixes)
        -- EXECUTE fix_sql;
    END LOOP;
END $$;

-- =============================================================================
-- ALTERNATIVE: Apply fixes directly (EXECUTE the ALTER statements)
-- =============================================================================
-- Uncomment this section to automatically fix all functions:

/*
DO $$
DECLARE
    func_record RECORD;
    fix_sql TEXT;
    fixed_count INTEGER := 0;
BEGIN
    FOR func_record IN 
        SELECT 
            n.nspname as schema_name,
            p.proname as function_name,
            pg_get_function_identity_arguments(p.oid) as args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.prokind = 'f'
          AND pg_get_functiondef(p.oid) NOT LIKE '%SET search_path%'
    LOOP
        fix_sql := format('ALTER FUNCTION %I.%I(%s) SET search_path = public;',
                         func_record.schema_name,
                         func_record.function_name,
                         func_record.args);
        
        BEGIN
            EXECUTE fix_sql;
            fixed_count := fixed_count + 1;
            RAISE NOTICE 'Fixed: %.%(%)', 
                func_record.schema_name, 
                func_record.function_name,
                func_record.args;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to fix %.%: %', 
                func_record.function_name,
                func_record.args,
                SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE 'Total functions fixed: %', fixed_count;
END $$;
*/

-- =============================================================================
-- VERIFICATION: Check that all functions now have search_path set
-- =============================================================================
-- Run this after applying fixes to verify:
SELECT 
    n.nspname as schema_name,
    p.proname as function_name,
    CASE 
        WHEN pg_get_functiondef(p.oid) LIKE '%SET search_path%' THEN '✅ HAS search_path'
        ELSE '❌ MISSING search_path'
    END as status
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
ORDER BY 
    CASE WHEN pg_get_functiondef(p.oid) LIKE '%SET search_path%' THEN 1 ELSE 0 END,
    p.proname;
