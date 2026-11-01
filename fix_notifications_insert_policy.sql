-- Add missing INSERT policy for notifications table
-- This allows the system to create notifications for users

CREATE POLICY IF NOT EXISTS "System can insert notifications" ON notifications
    FOR INSERT WITH CHECK (true);

-- Alternative: Allow authenticated users to insert notifications
-- CREATE POLICY "Authenticated users can insert notifications" ON notifications
--     FOR INSERT WITH CHECK ((SELECT auth.uid()) IS NOT NULL);

-- Verify the policy was added
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'notifications'
ORDER BY policyname;