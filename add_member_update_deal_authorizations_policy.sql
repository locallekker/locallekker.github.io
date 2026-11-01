-- Fix: Allow members to update their own deal_authorizations after payment
-- Without this policy, members cannot set status='completed' and payment_completed_at
-- after successful Paystack payment, causing TPs to see "awaiting payment" indefinitely.

-- ==============================================================
-- 1. DEAL_AUTHORIZATIONS: Member UPDATE policy
-- ==============================================================
DROP POLICY IF EXISTS "Members can update their own deal authorizations" ON public.deal_authorizations;
DROP POLICY IF EXISTS "Members and trusted partners can update deal authorizations" ON public.deal_authorizations;

-- Create policy allowing members to update their OWN deal authorizations
-- Needed for payment completion flow (status → 'completed', payment_completed_at)
CREATE POLICY "Members can update their own deal authorizations"
ON public.deal_authorizations
FOR UPDATE
TO authenticated
USING (
  auth.uid() = member_id
)
WITH CHECK (
  auth.uid() = member_id
);

-- ==============================================================
-- 2. VIRTUAL_RECEIPTS: Member INSERT policy (ensure it exists)
-- ==============================================================
DROP POLICY IF EXISTS "Members and trusted partners can insert virtual receipts" ON public.virtual_receipts;
DROP POLICY IF EXISTS "Trusted partners can insert virtual receipts" ON public.virtual_receipts;

CREATE POLICY "Members and trusted partners can insert virtual receipts"
ON public.virtual_receipts
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.deal_authorizations
    WHERE deal_authorizations.id = virtual_receipts.deal_authorization_id
    AND deal_authorizations.member_id = auth.uid()
  )
  OR
  EXISTS (
    SELECT 1 FROM public.deal_authorizations
    WHERE deal_authorizations.id = virtual_receipts.deal_authorization_id
    AND deal_authorizations.trusted_partner_id = auth.uid()
  )
);

-- ==============================================================
-- 3. DEAL_RECEIPTS: Member INSERT policy (ensure it exists)
-- ==============================================================
DROP POLICY IF EXISTS "Members and trusted partners can insert receipts" ON public.deal_receipts;
DROP POLICY IF EXISTS "Trusted partners can insert receipts" ON public.deal_receipts;

CREATE POLICY "Members and trusted partners can insert receipts"
ON public.deal_receipts
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = member_id
  OR
  auth.uid() = trusted_partner_id
);

-- ==============================================================
-- VERIFICATION
-- ==============================================================
SELECT tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('deal_authorizations', 'virtual_receipts', 'deal_receipts')
  AND cmd IN ('UPDATE', 'INSERT')
ORDER BY tablename, cmd, policyname;
