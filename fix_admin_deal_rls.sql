-- Fix: Allow admins to fully manage deals (INSERT/UPDATE/DELETE) on trusted_partner_discounts
-- Issue: The existing admin INSERT policy requires businesses.allow_admin_deal_creation = true,
--        but that column defaults to false, so admin always gets RLS violation
-- Solution: Create an unconditional admin policy + set flag true for all existing businesses
-- Run this in Supabase SQL Editor

-- ============================================================================
-- STEP 1: Drop the conditional admin policies
-- ============================================================================
DROP POLICY IF EXISTS "Admins can create discounts when allowed" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Admins can update discounts when allowed" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Admins can delete discounts when allowed" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Admin full access to trusted_partner_discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Admins can manage all discounts" ON public.trusted_partner_discounts;

-- ============================================================================
-- STEP 2: Create unconditional admin ALL policy (checks admin role only)
-- ============================================================================
CREATE POLICY "Admins can manage all discounts"
ON public.trusted_partner_discounts
FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM public.memberships
        WHERE user_id = auth.uid() AND role = 'admin'
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.memberships
        WHERE user_id = auth.uid() AND role = 'admin'
    )
);

-- ============================================================================
-- STEP 3: Set allow_admin_deal_creation = true for ALL existing businesses
-- ============================================================================
UPDATE public.businesses
SET allow_admin_deal_creation = true
WHERE allow_admin_deal_creation IS NULL OR allow_admin_deal_creation = false;

-- ============================================================================
-- STEP 4: Also ensure deal_authorizations has admin policy
-- ============================================================================

-- deal_authorizations
DROP POLICY IF EXISTS "Admins can manage deal authorizations" ON public.deal_authorizations;
CREATE POLICY "Admins can manage deal authorizations"
ON public.deal_authorizations
FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM public.memberships
        WHERE user_id = auth.uid() AND role = 'admin'
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.memberships
        WHERE user_id = auth.uid() AND role = 'admin'
    )
);

-- ============================================================================
-- STEP 5: Verify
-- ============================================================================
SELECT schemaname, tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'trusted_partner_discounts'
ORDER BY policyname;
