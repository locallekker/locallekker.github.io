-- =============================================================================
-- CLEAN UP NOTIFICATIONS RLS - Remove Conflicting Policies
-- =============================================================================
-- Current issue: Multiple INSERT policies might be conflicting
-- Solution: Keep only the broad policy that allows cross-user notifications
-- =============================================================================

-- Drop the restrictive INSERT policy (redundant with the broader one)
DROP POLICY IF EXISTS "Users can insert own notifications" ON notifications;

-- Verify the remaining policies
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

-- Expected result:
-- INSERT: Only "Authenticated can insert notifications for any user"
-- SELECT: "Users can view own notifications" 
-- UPDATE: "notifications_update_policy"
-- DELETE: "Users can delete own notifications"
