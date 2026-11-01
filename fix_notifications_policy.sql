-- Fix the notifications INSERT policy to allow authenticated users to create notifications
-- Drop the existing policy if it exists
DROP POLICY IF EXISTS "System can insert notifications" ON notifications;

-- Create a more permissive policy that allows authenticated users to insert notifications
CREATE POLICY "Authenticated users can insert notifications" ON notifications
    FOR INSERT WITH CHECK ((SELECT auth.uid()) IS NOT NULL);

-- Alternative: Allow service role to insert (if using service key)
-- This would require using the service role key in the app, which is less secure
-- CREATE POLICY "Service role can insert notifications" ON notifications
--     FOR INSERT WITH CHECK (true);

-- Verify the policy
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'notifications'
ORDER BY policyname;