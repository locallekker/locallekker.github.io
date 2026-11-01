-- =============================================================================
-- Align deal_authorizations with the application data model so member deal
-- requests reliably appear on the Trusted Partner "Authorizations" badge.
--
-- Background
-- ----------
-- The app (DiscountService.createDealAuthorization) writes a deal request with:
--   * trusted_partner_id = the TP's *user id*  (profiles.id / auth.uid of owner)
--   * business_id        = the *business* UUID (businesses.id)
-- and the TP dashboard counts pending requests with:
--   ...WHERE business_id = <business owned by auth.uid()> AND status = 'pending'
--
-- However the original schema migration (20251013223100) modelled the business
-- link on `trusted_partner_id` (FK -> businesses.id) and its RLS gated TP
-- visibility on `trusted_partner_id IN (businesses of auth.uid())`. Because the
-- app actually stores the *user id* in trusted_partner_id and the *business*
-- UUID in business_id, that RLS never matches -> the trusted partner cannot
-- SELECT the row -> the Authorizations badge stays at 0 even though the request
-- was created successfully.
--
-- This migration makes the database match the app: it guarantees the business_id
-- column, keys RLS + realtime off business_id, and (re)adds the table to the
-- realtime publication so the badge updates the instant a request is submitted.
-- Idempotent and safe to re-run.
-- =============================================================================

BEGIN;

-- 1) Ensure the business_id column the app relies on exists.
ALTER TABLE public.deal_authorizations
  ADD COLUMN IF NOT EXISTS business_id UUID;

-- Backfill business_id for any legacy rows from their originating discount.
UPDATE public.deal_authorizations da
SET business_id = d.business_id
FROM public.trusted_partner_discounts d
WHERE da.discount_id = d.id
  AND da.business_id IS NULL
  AND d.business_id IS NOT NULL;

-- Foreign key (add only if missing; NOT VALID avoids failing on legacy rows
-- that may reference a since-deleted business while still enforcing new rows).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'deal_authorizations_business_id_fkey'
      AND conrelid = 'public.deal_authorizations'::regclass
  ) THEN
    ALTER TABLE public.deal_authorizations
      ADD CONSTRAINT deal_authorizations_business_id_fkey
      FOREIGN KEY (business_id) REFERENCES public.businesses(id) ON DELETE CASCADE
      NOT VALID;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_deal_authorizations_business_id
  ON public.deal_authorizations(business_id);

-- 2) Trusted-partner RLS must key off business_id (not trusted_partner_id).
--    Drop every historical variant of the TP view/update policy first so the
--    correct, business_id-based ones are authoritative.
DROP POLICY IF EXISTS "Business owners can view authorizations for their business" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Business owners can update authorizations for their business" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Trusted partners can view authorizations for their business" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Trusted partners can update authorizations for their business" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Business owners can view their authorizations" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Business owners can update their authorizations" ON public.deal_authorizations;

CREATE POLICY "Business owners can view authorizations for their business"
  ON public.deal_authorizations
  FOR SELECT
  USING (
    business_id IN (
      SELECT id FROM public.businesses WHERE owner_member_id = auth.uid()
    )
  );

CREATE POLICY "Business owners can update authorizations for their business"
  ON public.deal_authorizations
  FOR UPDATE
  USING (
    business_id IN (
      SELECT id FROM public.businesses WHERE owner_member_id = auth.uid()
    )
  );

-- 3) Realtime: ensure the badge updates the instant a request is inserted/updated.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'deal_authorizations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.deal_authorizations;
  END IF;
END $$;

-- FULL replica identity so UPDATE events carry business_id for the app's filter.
ALTER TABLE public.deal_authorizations REPLICA IDENTITY FULL;

COMMIT;

-- Diagnostic (run manually): confirm the active TP SELECT policy now uses business_id
-- SELECT policyname, cmd, qual
-- FROM pg_policies
-- WHERE schemaname = 'public'
--   AND tablename = 'deal_authorizations'
--   AND cmd = 'SELECT'
-- ORDER BY policyname;
