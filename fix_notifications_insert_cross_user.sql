-- =============================================================================
-- FIX NOTIFICATIONS INSERT RLS POLICY - ALLOW CROSS-USER NOTIFICATIONS
-- =============================================================================
-- This script fixes the RLS policy to allow trusted partners to create
-- notifications for members when approving/rejecting deal authorizations.
-- =============================================================================

-- Drop the existing restrictive insert policy
DROP POLICY IF EXISTS "Authenticated members can insert notifications" ON notifications;
DROP POLICY IF EXISTS "notifications_insert_policy" ON notifications;
DROP POLICY IF EXISTS "Allow insert for any user" ON notifications;
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON notifications;

-- Create a new policy that allows any authenticated user to insert notifications
-- This is necessary because trusted partners need to create notifications for members
CREATE POLICY "Allow authenticated users to create notifications" ON notifications
FOR INSERT
TO authenticated
WITH CHECK (true);

-- Verify the policy was created
SELECT 
    policyname,
    cmd,
    roles,
    with_check
FROM pg_policies
WHERE schemaname = 'public' 
  AND tablename = 'notifications' 
  AND cmd = 'INSERT'
ORDER BY policyname;
