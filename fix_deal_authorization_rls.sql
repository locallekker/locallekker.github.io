-- Fix RLS policies for deal_authorizations table to use correct column name
-- The businesses table uses 'owner_member_id' not 'owner_id'

-- Drop existing policies that use the wrong column name
DROP POLICY IF EXISTS "Trusted partners can view authorizations for their business" ON deal_authorizations;
DROP POLICY IF EXISTS "Trusted partners can update authorizations for their business" ON deal_authorizations;

-- Recreate policies with correct column name
CREATE POLICY "Trusted partners can view authorizations for their business" ON deal_authorizations
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM businesses
            WHERE businesses.id = deal_authorizations.trusted_partner_id
            AND businesses.owner_member_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Trusted partners can update authorizations for their business" ON deal_authorizations
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM businesses
            WHERE businesses.id = deal_authorizations.trusted_partner_id
            AND businesses.owner_member_id = (SELECT auth.uid())
        )
    );

-- Also check if the deal_authorizations table exists and has RLS enabled
SELECT schemaname, tablename, rowsecurity FROM pg_tables WHERE tablename = 'deal_authorizations';

-- Check existing policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'deal_authorizations'
ORDER BY policyname;