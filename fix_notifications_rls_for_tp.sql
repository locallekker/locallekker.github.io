-- =============================================================================
-- FIX NOTIFICATIONS RLS - Allow Trusted Partners to Notify Members
-- =============================================================================
-- Problem: When TP approves/rejects deals, they need to create notifications
-- for members, but RLS blocks cross-user notification creation
-- Solution: Allow any authenticated user to insert notifications for any user
-- =============================================================================

-- Step 1: Drop existing INSERT policy
DROP POLICY IF EXISTS "Authenticated members can insert notifications" ON notifications;
DROP POLICY IF EXISTS "System can insert notifications" ON notifications;
DROP POLICY IF EXISTS "notifications_insert_public" ON notifications;
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON notifications;

-- Step 2: Create new INSERT policy that allows authenticated users to insert for anyone
-- This is safe because:
-- - Only authenticated users can insert
-- - Application logic controls who can trigger notifications
-- - RLS still protects SELECT (users can only see their own)
CREATE POLICY "Authenticated can insert notifications for any user" 
ON notifications
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() IS NOT NULL);

-- Note: This allows TPs to create notifications for members, admins to create
-- notifications for anyone, and the system to send notifications

-- Step 3: Verify policies
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
WHERE tablename = 'notifications'
ORDER BY cmd, policyname;
