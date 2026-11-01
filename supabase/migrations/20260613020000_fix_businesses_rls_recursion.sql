-- Migration: Fix businesses RLS recursion by using non-recursive policies
-- Date: 2026-06-13

BEGIN;

ALTER TABLE public.businesses ENABLE ROW LEVEL SECURITY;

-- Drop legacy/overlapping policies that can cause recursion via chained table checks.
DROP POLICY IF EXISTS "Members can view all businesses" ON public.businesses;
DROP POLICY IF EXISTS "Users can view all businesses" ON public.businesses;
DROP POLICY IF EXISTS "Authenticated users can view all businesses" ON public.businesses;
DROP POLICY IF EXISTS "Public can view verified businesses" ON public.businesses;
DROP POLICY IF EXISTS "Users can view own business" ON public.businesses;
DROP POLICY IF EXISTS "Users can view their own business" ON public.businesses;
DROP POLICY IF EXISTS "Trusted partners can view own business" ON public.businesses;
DROP POLICY IF EXISTS "Business owners can update their business" ON public.businesses;
DROP POLICY IF EXISTS "Users can update own business" ON public.businesses;
DROP POLICY IF EXISTS "Users can update their own business" ON public.businesses;
DROP POLICY IF EXISTS "Trusted partners can update own business" ON public.businesses;
DROP POLICY IF EXISTS "Authenticated members can create businesses" ON public.businesses;
DROP POLICY IF EXISTS "Authenticated users can create businesses" ON public.businesses;
DROP POLICY IF EXISTS "Users can insert their own business" ON public.businesses;
DROP POLICY IF EXISTS "Users can delete their own business" ON public.businesses;
DROP POLICY IF EXISTS "Business owners can delete their business" ON public.businesses;
DROP POLICY IF EXISTS "Service role can manage all businesses" ON public.businesses;
DROP POLICY IF EXISTS "Service role can manage businesses" ON public.businesses;
DROP POLICY IF EXISTS "Admins can manage all businesses" ON public.businesses;
DROP POLICY IF EXISTS "Admins can manage all businesses via JWT" ON public.businesses;

-- Safe baseline policies.
CREATE POLICY "Authenticated users can view all businesses"
  ON public.businesses
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Business owners can update their business"
  ON public.businesses
  FOR UPDATE
  TO authenticated
  USING (owner_member_id = auth.uid())
  WITH CHECK (owner_member_id = auth.uid());

CREATE POLICY "Authenticated users can create businesses"
  ON public.businesses
  FOR INSERT
  TO authenticated
  WITH CHECK (owner_member_id = auth.uid());

CREATE POLICY "Business owners can delete their business"
  ON public.businesses
  FOR DELETE
  TO authenticated
  USING (owner_member_id = auth.uid());

-- Service role keeps full operational access.
CREATE POLICY "Service role can manage all businesses"
  ON public.businesses
  FOR ALL
  TO authenticated
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Admin access via JWT claims only (no table subqueries, no recursion risk).
CREATE POLICY "Admins can manage all businesses via JWT"
  ON public.businesses
  FOR ALL
  TO authenticated
  USING (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'user_type', '') = 'admin'
    OR coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin'
  )
  WITH CHECK (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'user_type', '') = 'admin'
    OR coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin'
  );

COMMIT;
