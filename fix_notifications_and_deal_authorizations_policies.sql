-- =============================================================================
-- FIX RLS: notifications insert + deal_authorizations business-aligned policies
-- =============================================================================
-- Why: App inserts notifications on behalf of other users (trusted partner -> member)
-- and queries/updates deal_authorizations by business ownership. This script ensures
-- RLS policies match those flows and removes conflicting duplicates.
-- Safe: Uses DROP POLICY IF EXISTS and re-creates with stable names.
-- =============================================================================

-- ==========================
-- notifications (public)
-- ==========================
-- Ensure RLS is enabled
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Drop any duplicate/old INSERT policies by common names
DROP POLICY IF EXISTS "Authenticated members can insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_policy" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_authenticated" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_public" ON public.notifications;
DROP POLICY IF EXISTS "Allow authenticated users to create notifications" ON public.notifications;
DROP POLICY IF EXISTS "System can insert notifications" ON public.notifications;

-- Keep SELECT/UPDATE for row ownership (members see and update their own)
DROP POLICY IF EXISTS notifications_select_own ON public.notifications;
CREATE POLICY notifications_select_own ON public.notifications
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS notifications_update_own ON public.notifications;
CREATE POLICY notifications_update_own ON public.notifications
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid());

-- Single, permissive INSERT policy: any authenticated user can insert any notification
-- Needed so trusted partners can notify members
CREATE POLICY notifications_insert_authenticated ON public.notifications
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- ==========================
-- deal_authorizations (public)
-- ==========================
-- Ensure RLS is enabled
ALTER TABLE public.deal_authorizations ENABLE ROW LEVEL SECURITY;

-- Remove incorrect foreign key constraint (trusted_partner_id is a user ID, not a business ID)
ALTER TABLE public.deal_authorizations 
DROP CONSTRAINT IF EXISTS deal_authorizations_trusted_partner_id_fkey;

-- Clean up common legacy policy names (no-op if absent)
DROP POLICY IF EXISTS "Members can view their authorizations" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Members can insert their authorizations" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Members can insert their own authorizations" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Members can view their own authorizations" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Business owners can view their authorizations" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Business owners can update their authorizations" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Trusted partners can view authorizations for their business" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Trusted partners can view deal authorizations for their busines" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Trusted partners can update authorizations for their business" ON public.deal_authorizations;

-- Member can see and create their own deal authorizations
DROP POLICY IF EXISTS deal_auth_select_member ON public.deal_authorizations;
CREATE POLICY deal_auth_select_member ON public.deal_authorizations
  FOR SELECT
  TO authenticated
  USING (member_id = auth.uid());

DROP POLICY IF EXISTS deal_auth_insert_member ON public.deal_authorizations;
CREATE POLICY deal_auth_insert_member ON public.deal_authorizations
  FOR INSERT
  TO authenticated
  WITH CHECK (member_id = auth.uid());

-- Trusted partner (business owner) can view and update deal auths for their business
-- Aligns with app code that stores business_id and checks ownership via businesses.owner_member_id
DROP POLICY IF EXISTS deal_auth_select_business ON public.deal_authorizations;
CREATE POLICY deal_auth_select_business ON public.deal_authorizations
  FOR SELECT
  TO authenticated
  USING (
    business_id IN (
      SELECT b.id FROM public.businesses b WHERE b.owner_member_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS deal_auth_update_business ON public.deal_authorizations;
CREATE POLICY deal_auth_update_business ON public.deal_authorizations
  FOR UPDATE
  TO authenticated
  USING (
    business_id IN (
      SELECT b.id FROM public.businesses b WHERE b.owner_member_id = auth.uid()
    )
  );

-- Helpful indexes (no-ops if already exist)
CREATE INDEX IF NOT EXISTS idx_businesses_owner_member_id ON public.businesses(owner_member_id);
CREATE INDEX IF NOT EXISTS idx_deal_auth_business_id ON public.deal_authorizations(business_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);

-- ==========================
-- Verification queries
-- ==========================
-- List effective policies
SELECT schemaname, tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('notifications', 'deal_authorizations')
ORDER BY tablename, cmd, policyname;
