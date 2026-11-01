-- Verification SQL for Recent Fixes
-- Run this in Supabase SQL Editor to confirm schema matches code

-- ============================================================================
-- 1. VERIFY PROFILES TABLE COLUMNS
-- ============================================================================
SELECT 
    '1. PROFILES TABLE STRUCTURE' as check_section,
    column_name,
    data_type,
    is_nullable,
    CASE 
        WHEN column_name IN ('name', 'surname', 'email', 'id') THEN '✅ Required by app'
        WHEN column_name = 'full_name' THEN '❌ SHOULD NOT EXIST - App uses name + surname'
        ELSE '✓ Optional'
    END as status
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'profiles'
ORDER BY ordinal_position;

-- ============================================================================
-- 2. CHECK FOR PROBLEMATIC full_name COLUMN
-- ============================================================================
SELECT 
    '2. FULL_NAME COLUMN CHECK' as check_section,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = 'profiles' 
              AND column_name = 'full_name'
        ) 
        THEN '❌ ERROR: full_name column exists - this will break the app'
        ELSE '✅ CORRECT: full_name column does NOT exist'
    END as result;

-- ============================================================================
-- 3. VERIFY DEAL_AUTHORIZATIONS TABLE STRUCTURE
-- ============================================================================
SELECT 
    '3. DEAL_AUTHORIZATIONS TABLE' as check_section,
    column_name,
    data_type,
    is_nullable,
    CASE 
        WHEN column_name IN ('id', 'member_id', 'discount_id', 'trusted_partner_id', 
                             'business_id', 'payment_method', 'amount', 'status') 
        THEN '✅ Required'
        ELSE '✓ Optional'
    END as status
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'deal_authorizations'
ORDER BY ordinal_position;

-- ============================================================================
-- 4. VERIFY FOREIGN KEY RELATIONSHIPS
-- ============================================================================
SELECT 
    '4. DEAL_AUTHORIZATIONS FOREIGN KEYS' as check_section,
    conname as constraint_name,
    pg_get_constraintdef(c.oid) as constraint_definition,
    CASE 
        WHEN conname LIKE '%member_id%' AND pg_get_constraintdef(c.oid) LIKE '%profiles%' 
        THEN '✅ member_id -> profiles(id)'
        WHEN conname LIKE '%business_id%' AND pg_get_constraintdef(c.oid) LIKE '%businesses%' 
        THEN '✅ business_id -> businesses(id)'
        WHEN conname LIKE '%discount_id%' 
        THEN '✅ discount_id -> trusted_partner_discounts(id)'
        ELSE '✓ Other FK'
    END as status
FROM pg_constraint c
JOIN pg_namespace n ON n.oid = c.connamespace
WHERE contype = 'f'
  AND n.nspname = 'public'
  AND conrelid = 'deal_authorizations'::regclass;

-- ============================================================================
-- 5. TEST QUERY - SIMULATE APP BEHAVIOR
-- ============================================================================
-- This simulates what the app does when fetching member details
SELECT 
    '5. TEST MEMBER NAME QUERY' as check_section,
    id,
    name,
    surname,
    COALESCE(name || ' ' || surname, 'A member') as constructed_full_name,
    '✅ Query works - matches app code' as status
FROM profiles
LIMIT 3;

-- ============================================================================
-- 6. VERIFY PAYSTACK CUSTOMER CODE COLUMN
-- ============================================================================
SELECT 
    '6. PAYSTACK INTEGRATION COLUMNS' as check_section,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = 'profiles' 
              AND column_name = 'paystack_customer_code'
        ) 
        THEN '✅ paystack_customer_code exists'
        ELSE '⚠️ WARNING: paystack_customer_code missing'
    END as result;

-- ============================================================================
-- 7. SUMMARY REPORT
-- ============================================================================
SELECT 
    '7. SUMMARY - CRITICAL CHECKS' as check_section,
    (SELECT COUNT(*) FROM information_schema.columns 
     WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'name') as has_name_column,
    (SELECT COUNT(*) FROM information_schema.columns 
     WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'surname') as has_surname_column,
    (SELECT COUNT(*) FROM information_schema.columns 
     WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'full_name') as has_full_name_column,
    CASE 
        WHEN (SELECT COUNT(*) FROM information_schema.columns 
              WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'full_name') = 0
             AND (SELECT COUNT(*) FROM information_schema.columns 
                  WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'name') = 1
             AND (SELECT COUNT(*) FROM information_schema.columns 
                  WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'surname') = 1
        THEN '✅ SCHEMA MATCHES CODE - All fixes should work!'
        ELSE '❌ SCHEMA MISMATCH - Review issues above'
    END as overall_status;
