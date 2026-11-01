-- Fix virtual_receipts INSERT policy to allow trusted partners to create receipts
-- Currently there is NO INSERT policy, which blocks all inserts

-- Add INSERT policy for trusted partners
CREATE POLICY "Trusted partners can insert virtual receipts" ON public.virtual_receipts
  FOR INSERT 
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.deal_authorizations
      WHERE deal_authorizations.id = virtual_receipts.deal_authorization_id
      AND deal_authorizations.trusted_partner_id = auth.uid()
    )
  );

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
WHERE tablename = 'virtual_receipts'
ORDER BY policyname;
