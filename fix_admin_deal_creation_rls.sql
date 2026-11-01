-- Fix: Give admins unconditional access to create/manage deals and upload
-- deal images for any trusted partner, without requiring allow_admin_deal_creation.
--
-- Root cause: previous policies gated admin access on
--   COALESCE(b.allow_admin_deal_creation, false) = true
-- which defaults to false, blocking all admin deal creation.
--
-- This migration replaces those conditional policies with unconditional
-- admin policies based on profiles.role = 'admin', consistent with the
-- partner-logos admin storage policy pattern.

begin;

-- ─── trusted_partner_discounts ───────────────────────────────────────────────

-- Drop old conditional admin policies (from add_admin_can_create_deals_permission.sql)
DROP POLICY IF EXISTS "Admins can create discounts when allowed"  ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Admins can update discounts when allowed"  ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Admins can delete discounts when allowed"  ON public.trusted_partner_discounts;

-- Drop old email-based full-access policy (from add_admin_discounts_policy.sql)
DROP POLICY IF EXISTS "Admin full access to trusted_partner_discounts" ON public.trusted_partner_discounts;

-- Single unconditional admin policy (ALL operations)
CREATE POLICY "Admins have full access to trusted_partner_discounts"
  ON public.trusted_partner_discounts
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role = 'admin'
    )
  );

-- ─── storage.objects (business-bills / deal_images) ──────────────────────────

-- Drop old conditional admin storage policy (from add_deal_images_rls_policies.sql)
DROP POLICY IF EXISTS "Admins can manage deal images" ON storage.objects;

-- Unconditional admin storage policy for deal images
CREATE POLICY "Admins can manage deal images"
  ON storage.objects
  FOR ALL
  USING (
    bucket_id = 'business-bills'
    AND name LIKE 'deal_images/%'
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role = 'admin'
    )
  )
  WITH CHECK (
    bucket_id = 'business-bills'
    AND name LIKE 'deal_images/%'
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role = 'admin'
    )
  );

commit;
