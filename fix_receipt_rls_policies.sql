-- Fix RLS policies to allow receipt generation from member context

-- 1. DROP existing restrictive policy on virtual_receipts if it exists
DROP POLICY IF EXISTS "Trusted partners can insert virtual receipts" ON public.virtual_receipts;

-- 2. CREATE new policy that allows BOTH members and trusted partners to insert
CREATE POLICY "Members and trusted partners can insert virtual receipts" 
ON public.virtual_receipts
FOR INSERT 
WITH CHECK (
  -- Allow if user is the member on the deal authorization
  EXISTS (
    SELECT 1 FROM public.deal_authorizations
    WHERE deal_authorizations.id = virtual_receipts.deal_authorization_id
    AND deal_authorizations.member_id = auth.uid()
  )
  OR
  -- Allow if user is the trusted partner on the deal authorization
  EXISTS (
    SELECT 1 FROM public.deal_authorizations
    WHERE deal_authorizations.id = virtual_receipts.deal_authorization_id
    AND deal_authorizations.trusted_partner_id = auth.uid()
  )
);

-- 3. DROP existing restrictive policy on deal_receipts if it exists
DROP POLICY IF EXISTS "Trusted partners can insert receipts" ON public.deal_receipts;

-- 4. CREATE new policy that allows BOTH members and trusted partners to insert
CREATE POLICY "Members and trusted partners can insert receipts" 
ON public.deal_receipts
FOR INSERT 
WITH CHECK (
  -- Allow if user is the member
  auth.uid() = member_id
  OR
  -- Allow if user is the trusted partner
  auth.uid() = trusted_partner_id
);

-- 5. Verify the new policies
SELECT 
  tablename,
  policyname,
  cmd,
  with_check
FROM pg_policies
WHERE tablename IN ('virtual_receipts', 'deal_receipts')
AND cmd = 'INSERT'
ORDER BY tablename;
