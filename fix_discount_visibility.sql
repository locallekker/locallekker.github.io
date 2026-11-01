-- Fix: Recreate the missing SELECT policy for trusted_partner_discounts
-- The cleanup script accidentally removed the "Users can view all discounts" policy

-- Ensure RLS is enabled
ALTER TABLE trusted_partner_discounts ENABLE ROW LEVEL SECURITY;

-- Recreate the SELECT policy that allows everyone to view discounts
DROP POLICY IF EXISTS "Users can view all discounts" ON trusted_partner_discounts;
CREATE POLICY "Users can view all discounts" ON trusted_partner_discounts
    FOR SELECT USING (true);

-- Keep the business owner management policy
DROP POLICY IF EXISTS "Business owners can manage their discounts" ON trusted_partner_discounts;
CREATE POLICY "Business owners can manage their discounts" ON trusted_partner_discounts
    FOR ALL USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- Verify the policies are in place
SELECT schemaname, tablename, policyname, cmd, qual
FROM pg_policies WHERE tablename = 'trusted_partner_discounts'
ORDER BY policyname;