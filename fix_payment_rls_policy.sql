-- Fix RLS policy to allow members to update payment_completed_at on their own deal authorizations
-- 
-- PROBLEM IDENTIFIED:
-- Current policies only allow:
--   - deal_auth_insert_member: Members can INSERT
--   - deal_auth_select_member: Members can SELECT
--   - deal_auth_update_business: Businesses can UPDATE
-- Missing: Members cannot UPDATE their own authorizations!
--
-- SOLUTION: Add policy allowing members to UPDATE their own deal_authorizations
-- This is needed so members can set payment_completed_at after Paystack payment

-- Create policy allowing members to update their own authorizations
-- Specifically needed for payment_completed_at timestamp after payment
CREATE POLICY "deal_auth_update_member"
ON deal_authorizations
FOR UPDATE
TO authenticated
USING (member_id = auth.uid())
WITH CHECK (member_id = auth.uid());

-- Verify the policy was created
SELECT 
  policyname,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'deal_authorizations' 
ORDER BY cmd, policyname;
