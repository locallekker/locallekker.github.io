-- Add per-business permission for admins to create deals on behalf of a trusted partner

-- 1) Schema: add boolean flag on businesses
ALTER TABLE public.businesses
  ADD COLUMN IF NOT EXISTS allow_admin_deal_creation BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.businesses.allow_admin_deal_creation IS 'When true, admins may create discounts for this business on behalf of the owner.';

CREATE INDEX IF NOT EXISTS idx_businesses_allow_admin_deal_creation
  ON public.businesses(allow_admin_deal_creation);

-- 2) RLS: allow admin INSERT to trusted_partner_discounts only when the business has opted in
DROP POLICY IF EXISTS "Admins can create discounts when allowed" ON public.trusted_partner_discounts;
CREATE POLICY "Admins can create discounts when allowed" ON public.trusted_partner_discounts
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      JOIN public.businesses b
        ON b.id = trusted_partner_discounts.business_id
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
        AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
  );

-- 3) RLS: allow admin UPDATE to trusted_partner_discounts when the business has opted in
DROP POLICY IF EXISTS "Admins can update discounts when allowed" ON public.trusted_partner_discounts;
CREATE POLICY "Admins can update discounts when allowed" ON public.trusted_partner_discounts
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      JOIN public.businesses b
        ON b.id = trusted_partner_discounts.business_id
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
        AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      JOIN public.businesses b
        ON b.id = trusted_partner_discounts.business_id
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
        AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
  );

-- 4) RLS: allow admin DELETE to trusted_partner_discounts when the business has opted in
DROP POLICY IF EXISTS "Admins can delete discounts when allowed" ON public.trusted_partner_discounts;
CREATE POLICY "Admins can delete discounts when allowed" ON public.trusted_partner_discounts
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      JOIN public.businesses b
        ON b.id = trusted_partner_discounts.business_id
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
        AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
  );

-- Verification (manual):
--  a) Set businesses.allow_admin_deal_creation = true for a target business.
--  b) As admin session, insert into trusted_partner_discounts with that trusted_partner_id; should succeed.
--  c) Set flag to false; admin insert should fail while owner can still insert.
