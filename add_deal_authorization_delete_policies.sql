-- Add DELETE policies for deal_authorizations table
-- Allows trusted partners and admins to delete deal authorization requests

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Trusted partners can delete deal authorizations" ON deal_authorizations;
DROP POLICY IF EXISTS "Admins can delete deal authorizations" ON deal_authorizations;
DROP POLICY IF EXISTS "Members can delete their own deal authorizations" ON deal_authorizations;

-- Allow trusted partners to delete deal authorizations for their business
CREATE POLICY "Trusted partners can delete deal authorizations" ON deal_authorizations
    FOR DELETE USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- Allow admins to delete any deal authorization
CREATE POLICY "Admins can delete deal authorizations" ON deal_authorizations
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- Allow members to delete their own pending deal authorizations
CREATE POLICY "Members can delete their own deal authorizations" ON deal_authorizations
    FOR DELETE USING (
        member_id = auth.uid() AND status = 'pending'
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
WHERE tablename = 'deal_authorizations'
ORDER BY cmd, policyname;
