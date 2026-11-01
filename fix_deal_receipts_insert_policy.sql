-- Fix deal_receipts INSERT policy to allow trusted partners to create receipts
-- The trusted partner creates the receipt on behalf of the member after payment

-- Drop the old policy that only allowed members
DROP POLICY IF EXISTS "System can insert receipts" ON public.deal_receipts;

-- Create new policy: Trusted partners can insert receipts for their businesses
CREATE POLICY "Trusted partners can insert receipts" ON public.deal_receipts
  FOR INSERT 
  WITH CHECK (auth.uid() = trusted_partner_id);

-- Verification query
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE tablename = 'deal_receipts'
ORDER BY policyname;
