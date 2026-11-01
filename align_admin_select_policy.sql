-- Align admin SELECT policy to use memberships (consistent with other admin checks)
-- Idempotent: drops and recreates the policy

BEGIN;

DROP POLICY IF EXISTS "Admin can view all trusted partner discounts" ON public.trusted_partner_discounts;

CREATE POLICY "Admin can view all trusted partner discounts" ON public.trusted_partner_discounts
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
    )
  );

COMMIT;
