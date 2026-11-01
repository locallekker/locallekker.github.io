-- =============================================================================
-- FIX DEAL AUTHORIZATION FOREIGN KEY RLS ISSUE
-- =============================================================================
-- Issue: When members request deals, the insert fails with foreign key violation
-- on deal_authorizations.business_id because RLS policies may prevent the FK
-- check from seeing the businesses table records.
--
-- Solution: 
-- 1. Ensure businesses table has proper grants for authenticated role
-- 2. Ensure RLS policies allow FK checks to succeed
-- 3. Verify deal_authorizations INSERT policy matches business_id lookup
-- =============================================================================

-- ==========================
-- Step 1: Grant access to businesses table
-- ==========================
-- Foreign key checks need to be able to see referenced rows
GRANT SELECT ON public.businesses TO authenticated;
GRANT SELECT ON public.trusted_partner_discounts TO authenticated;

-- ==========================
-- Step 2: Fix businesses table RLS policies
-- ==========================
ALTER TABLE public.businesses ENABLE ROW LEVEL SECURITY;

-- Drop existing policies
DROP POLICY IF EXISTS "Members can view all businesses" ON public.businesses;
DROP POLICY IF EXISTS "Users can view all businesses" ON public.businesses;
DROP POLICY IF EXISTS "Authenticated users can view all businesses" ON public.businesses;
DROP POLICY IF EXISTS "Public can view verified businesses" ON public.businesses;

-- Create a permissive SELECT policy for ALL authenticated users
-- This is CRITICAL for foreign key checks to work
CREATE POLICY "Authenticated users can view all businesses" ON public.businesses
  FOR SELECT
  TO authenticated
  USING (true);  -- All authenticated users can see all businesses

-- Keep UPDATE restricted to owners
DROP POLICY IF EXISTS "Business owners can update their business" ON public.businesses;
CREATE POLICY "Business owners can update their business" ON public.businesses
  FOR UPDATE
  TO authenticated
  USING (owner_member_id = auth.uid());

-- Keep INSERT for authenticated users
DROP POLICY IF EXISTS "Authenticated members can create businesses" ON public.businesses;
DROP POLICY IF EXISTS "Authenticated users can create businesses" ON public.businesses;
CREATE POLICY "Authenticated users can create businesses" ON public.businesses
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- ==========================
-- Step 3: Fix trusted_partner_discounts RLS policies
-- ==========================
ALTER TABLE public.trusted_partner_discounts ENABLE ROW LEVEL SECURITY;

-- Drop existing policies
DROP POLICY IF EXISTS "Members can view all discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Authenticated users can view all active discounts" ON public.trusted_partner_discounts;

-- Create permissive SELECT policy for FK checks and deal browsing
CREATE POLICY "Authenticated users can view all active discounts" ON public.trusted_partner_discounts
  FOR SELECT
  TO authenticated
  USING (true);  -- All authenticated users can see all discounts

-- Keep UPDATE/INSERT restricted to business owners
DROP POLICY IF EXISTS "Business owners can update their discounts" ON public.trusted_partner_discounts;
CREATE POLICY "Business owners can update their discounts" ON public.trusted_partner_discounts
  FOR UPDATE
  TO authenticated
  USING (
    business_id IN (
      SELECT id FROM public.businesses WHERE owner_member_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Business owners can create discounts" ON public.trusted_partner_discounts;
CREATE POLICY "Business owners can create discounts" ON public.trusted_partner_discounts
  FOR INSERT
  TO authenticated
  WITH CHECK (
    business_id IN (
      SELECT id FROM public.businesses WHERE owner_member_id = auth.uid()
    )
  );

-- ==========================
-- Step 4: Verify deal_authorizations RLS policies
-- ==========================
ALTER TABLE public.deal_authorizations ENABLE ROW LEVEL SECURITY;

-- Drop any existing INSERT policies
DROP POLICY IF EXISTS "Members can insert their authorizations" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Members can insert their own authorizations" ON public.deal_authorizations;
DROP POLICY IF EXISTS deal_auth_insert_member ON public.deal_authorizations;

-- Create INSERT policy that properly validates member_id
-- This policy MUST allow the FK check to see the business record
CREATE POLICY deal_auth_insert_member ON public.deal_authorizations
  FOR INSERT
  TO authenticated
  WITH CHECK (member_id = auth.uid());
  -- Note: No restriction on business_id here - FK will validate it exists
  -- and the SELECT policy on businesses allows the FK check to see all businesses

-- Keep SELECT policies
DROP POLICY IF EXISTS deal_auth_select_member ON public.deal_authorizations;
CREATE POLICY deal_auth_select_member ON public.deal_authorizations
  FOR SELECT
  TO authenticated
  USING (member_id = auth.uid());

DROP POLICY IF EXISTS deal_auth_select_business ON public.deal_authorizations;
CREATE POLICY deal_auth_select_business ON public.deal_authorizations
  FOR SELECT
  TO authenticated
  USING (
    business_id IN (
      SELECT b.id FROM public.businesses b WHERE b.owner_member_id = auth.uid()
    )
  );

-- Keep UPDATE policy
DROP POLICY IF EXISTS deal_auth_update_business ON public.deal_authorizations;
CREATE POLICY deal_auth_update_business ON public.deal_authorizations
  FOR UPDATE
  TO authenticated
  USING (
    business_id IN (
      SELECT b.id FROM public.businesses b WHERE b.owner_member_id = auth.uid()
    )
  );

-- ==========================
-- Step 5: Verify foreign key constraints exist
-- ==========================
-- Ensure the foreign key constraint exists and is properly configured
ALTER TABLE public.deal_authorizations 
DROP CONSTRAINT IF EXISTS deal_authorizations_business_id_fkey;

ALTER TABLE public.deal_authorizations 
ADD CONSTRAINT deal_authorizations_business_id_fkey 
FOREIGN KEY (business_id) REFERENCES public.businesses(id) ON DELETE CASCADE;

-- Also verify the discount FK
ALTER TABLE public.deal_authorizations 
DROP CONSTRAINT IF EXISTS deal_authorizations_discount_id_fkey;

ALTER TABLE public.deal_authorizations 
ADD CONSTRAINT deal_authorizations_discount_id_fkey 
FOREIGN KEY (discount_id) REFERENCES public.trusted_partner_discounts(id) ON DELETE SET NULL;

-- ==========================
-- Step 6: Create helpful indexes
-- ==========================
CREATE INDEX IF NOT EXISTS idx_businesses_owner_member_id ON public.businesses(owner_member_id);
CREATE INDEX IF NOT EXISTS idx_deal_auth_business_id ON public.deal_authorizations(business_id);
CREATE INDEX IF NOT EXISTS idx_deal_auth_member_id ON public.deal_authorizations(member_id);
CREATE INDEX IF NOT EXISTS idx_discounts_business_id ON public.trusted_partner_discounts(business_id);

-- ==========================
-- Verification Queries
-- ==========================
-- 1. Check grants
SELECT 
  grantee, 
  privilege_type,
  table_name
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name IN ('businesses', 'trusted_partner_discounts', 'deal_authorizations')
  AND grantee = 'authenticated'
ORDER BY table_name, privilege_type;

-- 2. Check RLS policies
SELECT 
  schemaname,
  tablename,
  policyname,
  cmd,
  roles,
  CASE 
    WHEN cmd = 'SELECT' THEN 'USING: ' || COALESCE(qual::text, 'NULL')
    WHEN cmd = 'INSERT' THEN 'WITH CHECK: ' || COALESCE(with_check::text, 'NULL')
    WHEN cmd = 'UPDATE' THEN 'USING: ' || COALESCE(qual::text, 'NULL')
    ELSE 'OTHER'
  END as policy_expression
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('businesses', 'trusted_partner_discounts', 'deal_authorizations')
ORDER BY tablename, cmd, policyname;

-- 3. Check foreign key constraints
SELECT
  tc.constraint_name,
  tc.table_name,
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
ORDER BY kcu.column_name;

-- ==========================
-- Test Query
-- ==========================
-- This should return businesses that can be used for deal authorizations
-- Run this as the authenticated user to verify RLS allows seeing businesses
SELECT 
  id,
  name,
  owner_member_id
FROM public.businesses
ORDER BY name
LIMIT 5;
