-- Add the missing INSERT policy for deal authorizations
-- First check if it already exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'deal_authorizations'
        AND policyname = 'Members can insert their own authorizations'
    ) THEN
        CREATE POLICY "Members can insert their own authorizations" ON deal_authorizations
            FOR INSERT WITH CHECK ((SELECT auth.uid()) = member_id);
    END IF;
END $$;

-- Verify all policies are now present
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'deal_authorizations'
ORDER BY policyname;