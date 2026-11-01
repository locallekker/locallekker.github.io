-- =============================================================================
-- FIX: Allow admins to see admin_group broadcast notifications
-- =============================================================================
-- This modifies the SELECT policy to allow users to see:
-- 1. Their own notifications (user_id = auth.uid())
-- 2. Admin broadcast notifications if they are an admin (user_id = 'admin_group')
-- =============================================================================

-- Drop the old SELECT policy
DROP POLICY IF EXISTS "notifications_select_own" ON notifications;

-- Create new SELECT policy that includes admin broadcasts
CREATE POLICY "notifications_select_own" 
ON notifications
FOR SELECT
TO public
USING (
  user_id = auth.uid() 
  OR (user_id = 'admin_group' AND EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  ))
  OR auth.uid() IS NULL
);

-- Verify the policy
SELECT 
  policyname,
  cmd,
  roles,
  with_check::text
FROM pg_policies
WHERE tablename = 'notifications' 
AND policyname = 'notifications_select_own';
