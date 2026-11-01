-- =============================================================================
-- DIAGNOSE DEAL AUTHORIZATION FOREIGN KEY ISSUE
-- =============================================================================
-- This script helps diagnose why deal authorization requests are failing
-- Run this to identify the specific issue
-- =============================================================================

-- 0. Check what columns exist in businesses table
SELECT 
  'Businesses Table Columns' as check_name,
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'businesses'
ORDER BY ordinal_position;

-- 1. Check if businesses table has RLS enabled and what policies exist
SELECT 
  'Businesses Table RLS Status' as check_name,
  schemaname,
  tablename,
  rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'businesses';

-- 2. Check businesses table policies
SELECT 
  'Businesses Policies' as check_name,
  policyname,
  cmd,
  permissive,
  roles,
  qual::text as using_clause,
  with_check::text as with_check_clause
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'businesses'
ORDER BY cmd, policyname;

-- 3. Check if authenticated role has SELECT grant on businesses
SELECT 
  'Businesses Grants' as check_name,
  grantee,
  privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'businesses'
  AND grantee IN ('authenticated', 'public')
ORDER BY grantee, privilege_type;

-- 4. Check deal_authorizations foreign key constraints
SELECT
  'Deal Auth Foreign Keys' as check_name,
  tc.constraint_name,
  kcu.column_name,
  ccu.table_name AS foreign_table,
  ccu.column_name AS foreign_column,
  rc.delete_rule
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
LEFT JOIN information_schema.referential_constraints AS rc
  ON tc.constraint_name = rc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_name = 'deal_authorizations'
  AND kcu.column_name = 'business_id'
ORDER BY kcu.column_name;

-- 5. Check deal_authorizations INSERT policies
SELECT 
  'Deal Auth INSERT Policies' as check_name,
  policyname,
  cmd,
  permissive,
  roles,
  with_check::text as with_check_clause
FROM pg_policies
WHERE schemaname = 'public' 
  AND tablename = 'deal_authorizations'
  AND cmd = 'INSERT'
ORDER BY policyname;

-- 6. Check if there are any businesses in the table
SELECT 
  'Business Count' as check_name,
  COUNT(*) as total_businesses
FROM public.businesses;

-- 7. Sample businesses (first 5)
SELECT 
  'Sample Businesses' as check_name,
  id,
  name,
  owner_member_id
FROM public.businesses
ORDER BY id DESC
LIMIT 5;

-- 8. Check trusted_partner_discounts and their business_ids
SELECT 
  'Sample Discounts' as check_name,
  tpd.id as discount_id,
  tpd.name as discount_name,
  tpd.business_id,
  tpd.trusted_partner_id,
  b.name as business_name,
  b.owner_member_id as business_owner_id,
  CASE 
    WHEN tpd.business_id IS NULL THEN '❌ No business_id'
    WHEN b.id IS NULL THEN '❌ Business not found'
    ELSE '✅ Valid'
  END as status
FROM public.trusted_partner_discounts tpd
LEFT JOIN public.businesses b ON b.id = tpd.business_id
ORDER BY tpd.id DESC
LIMIT 10;

-- 9. Check for discounts with NULL or invalid business_ids
SELECT 
  'Invalid Discount Business IDs' as check_name,
  COUNT(*) as count_discounts_with_null_business_id
FROM public.trusted_partner_discounts
WHERE business_id IS NULL;

-- 10. Check for discounts pointing to non-existent businesses
SELECT 
  'Orphaned Discounts' as check_name,
  COUNT(*) as count_orphaned_discounts
FROM public.trusted_partner_discounts tpd
LEFT JOIN public.businesses b ON b.id = tpd.business_id
WHERE tpd.business_id IS NOT NULL
  AND b.id IS NULL;

-- ==========================
-- Summary and Recommendations
-- ==========================
SELECT 
  '=== SUMMARY ===' as section,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM pg_tables 
      WHERE schemaname = 'public' 
        AND tablename = 'businesses' 
        AND rowsecurity = false
    ) THEN 'RLS is DISABLED on businesses table - foreign key checks may fail'
    WHEN NOT EXISTS (
      SELECT 1 FROM information_schema.table_privileges
      WHERE table_schema = 'public'
        AND table_name = 'businesses'
        AND grantee = 'authenticated'
        AND privilege_type = 'SELECT'
    ) THEN 'authenticated role lacks SELECT grant on businesses table'
    WHEN NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' 
        AND tablename = 'businesses'
        AND cmd = 'SELECT'
        AND qual::text = 'true'
    ) THEN 'No permissive SELECT policy on businesses (RLS may block FK checks)'
    WHEN EXISTS (
      SELECT 1 FROM public.trusted_partner_discounts tpd
      LEFT JOIN public.businesses b ON b.id = tpd.business_id
      WHERE tpd.business_id IS NOT NULL
        AND b.id IS NULL
    ) THEN 'Some discounts reference non-existent businesses'
    ELSE 'Configuration looks correct'
  END as diagnosis,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM pg_tables 
      WHERE schemaname = 'public' 
        AND tablename = 'businesses' 
        AND rowsecurity = false
    ) THEN 'Run: ALTER TABLE public.businesses ENABLE ROW LEVEL SECURITY;'
    WHEN NOT EXISTS (
      SELECT 1 FROM information_schema.table_privileges
      WHERE table_schema = 'public'
        AND table_name = 'businesses'
        AND grantee = 'authenticated'
        AND privilege_type = 'SELECT'
    ) THEN 'Run: GRANT SELECT ON public.businesses TO authenticated;'
    WHEN NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' 
        AND tablename = 'businesses'
        AND cmd = 'SELECT'
        AND qual::text = 'true'
    ) THEN 'Run fix_deal_authorization_foreign_key_rls.sql to add permissive SELECT policy'
    WHEN EXISTS (
      SELECT 1 FROM public.trusted_partner_discounts tpd
      LEFT JOIN public.businesses b ON b.id = tpd.business_id
      WHERE tpd.business_id IS NOT NULL
        AND b.id IS NULL
    ) THEN 'Fix data: Update or delete discounts with invalid business_ids'
    ELSE 'No action needed'
  END as recommended_fix;
