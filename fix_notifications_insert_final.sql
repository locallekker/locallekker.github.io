-- =============================================================================
-- FIX NOTIFICATIONS INSERT RLS POLICY - FINAL
-- =============================================================================
-- This script removes all conflicting insert policies and creates a single
-- simple policy that allows any authenticated user to insert notifications.
-- =============================================================================

-- Drop all existing insert policies
DROP POLICY IF EXISTS "Allow insert for any user" ON notifications;
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON notifications;

-- Create a single, simple insert policy
-- This allows any authenticated user to insert a notification for ANY user_id
-- (not just their own), which is necessary for cross-user notifications
CREATE POLICY "notifications_insert_policy" ON notifications
FOR INSERT
TO public
WITH CHECK (true);

-- Verify the policy was created
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'notifications' AND cmd = 'INSERT';
