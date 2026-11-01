-- Add DELETE policies for trusted_partner_discounts (deals) table
-- Allows trusted partners and admins to permanently delete deals from the database

-- Drop existing delete policies if they exist
DROP POLICY IF EXISTS "Trusted partners can delete their own deals" ON trusted_partner_discounts;
DROP POLICY IF EXISTS "Admins can delete any deal" ON trusted_partner_discounts;
DROP POLICY IF EXISTS "Members can delete their own discounts" ON trusted_partner_discounts;

-- Allow trusted partners to delete their own deals
CREATE POLICY "Trusted partners can delete their own deals" ON trusted_partner_discounts
    FOR DELETE USING (auth.uid() = trusted_partner_id);

-- Allow admins to delete any deal
CREATE POLICY "Admins can delete any deal" ON trusted_partner_discounts
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- Verify policies
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual
FROM pg_policies
WHERE tablename = 'trusted_partner_discounts'
ORDER BY cmd, policyname;
