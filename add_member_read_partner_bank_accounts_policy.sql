-- ============================================================================
-- Add RLS policy: Members can read partner bank accounts for payment
-- ============================================================================
-- Problem: When a member has an approved deal authorization and tries to pay,
-- the app queries trusted_partner_bank_accounts to check if the partner's
-- banking is ready. But RLS only allows users to read their OWN bank accounts.
-- This means the member's query silently returns no rows, causing the
-- "Partner banking not ready" error even when the TP's banking IS active.
--
-- Fix: Allow authenticated users to SELECT from trusted_partner_bank_accounts
-- if they have an approved (or pending) deal authorization with that partner.
-- ============================================================================

-- Drop if exists (idempotent)
DROP POLICY IF EXISTS "Members can view partner bank accounts for payment" ON public.trusted_partner_bank_accounts;

-- Create policy: members with active deal authorizations can read the TP's bank account
CREATE POLICY "Members can view partner bank accounts for payment"
ON public.trusted_partner_bank_accounts
FOR SELECT
USING (
  -- Allow if the current user has an approved deal authorization with this partner
  EXISTS (
    SELECT 1
    FROM public.deal_authorizations da
    WHERE da.trusted_partner_id = trusted_partner_bank_accounts.user_id
      AND da.member_id = auth.uid()
      AND da.status IN ('approved', 'pending')
  )
);

-- Verify the policy was created
SELECT
  policyname,
  cmd,
  qual
FROM pg_policies
WHERE tablename = 'trusted_partner_bank_accounts'
ORDER BY policyname;
