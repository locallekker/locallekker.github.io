-- =============================================================================
-- QUICK FIX: Deal Authorization Foreign Key RLS Issue
-- =============================================================================
-- This is a minimal fix to allow deal authorization requests to work
-- Run this immediately if you need a quick solution
-- For comprehensive fix, run fix_deal_authorization_foreign_key_rls.sql
-- =============================================================================

-- Step 1: Grant SELECT on businesses table to authenticated users
-- This allows foreign key checks to see the referenced rows
GRANT SELECT ON public.businesses TO authenticated;

-- Step 2: Ensure RLS is enabled on businesses
ALTER TABLE public.businesses ENABLE ROW LEVEL SECURITY;

-- Step 3: Create or replace SELECT policy to allow all authenticated users to view businesses
-- This is CRITICAL - foreign key checks need to see the referenced rows
DROP POLICY IF EXISTS "Authenticated users can view all businesses" ON public.businesses;
CREATE POLICY "Authenticated users can view all businesses" ON public.businesses
  FOR SELECT
  TO authenticated
  USING (true);  -- Allow all authenticated users to see all businesses

-- Step 4: Verify the policy was created
SELECT 
  policyname,
  cmd,
  permissive,
  roles,
  qual::text as using_expression
FROM pg_policies
WHERE schemaname = 'public' 
  AND tablename = 'businesses'
  AND cmd = 'SELECT'
ORDER BY policyname;

-- Step 5: Test query - this should return businesses if policy is working
-- Run this as an authenticated user
SELECT 
  id,
  name,
  owner_member_id
FROM public.businesses
LIMIT 3;
