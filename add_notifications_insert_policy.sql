-- Add the missing INSERT policy for notifications table
-- PostgreSQL doesn't support IF NOT EXISTS for CREATE POLICY

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'notifications'
        AND policyname = 'System can insert notifications'
    ) THEN
        CREATE POLICY "System can insert notifications" ON notifications
            FOR INSERT WITH CHECK (true);
    END IF;
END $$;

-- Verify the policy was added
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'notifications'
ORDER BY policyname;