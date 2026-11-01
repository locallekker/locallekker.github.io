-- =============================================================================
-- FIX: Enable RLS on notifications_archive table
-- Issue: Security Advisor flagged missing RLS on public.notifications_archive
-- Solution: Enable RLS and add appropriate policies
-- =============================================================================

-- Enable RLS on notifications_archive table
ALTER TABLE notifications_archive ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- RLS POLICIES FOR notifications_archive
-- =============================================================================

-- Policy 1: Admins can view all archived notifications
DROP POLICY IF EXISTS "Admins can view archived notifications" ON notifications_archive;
CREATE POLICY "Admins can view archived notifications" 
ON notifications_archive
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
);

-- Policy 2: Users can view their own archived notifications
DROP POLICY IF EXISTS "Users can view own archived notifications" ON notifications_archive;
CREATE POLICY "Users can view own archived notifications" 
ON notifications_archive
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- Policy 3: Only system/admin can insert into archive (via service role)
DROP POLICY IF EXISTS "System can insert into archive" ON notifications_archive;
CREATE POLICY "System can insert into archive" 
ON notifications_archive
FOR INSERT
TO service_role
WITH CHECK (true);

-- Policy 4: Admins can delete old archived notifications for cleanup
DROP POLICY IF EXISTS "Admins can delete archived notifications" ON notifications_archive;
CREATE POLICY "Admins can delete archived notifications" 
ON notifications_archive
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
);

-- Grant appropriate permissions
GRANT SELECT ON notifications_archive TO authenticated;
GRANT INSERT, DELETE ON notifications_archive TO service_role;

-- Add index for better query performance
CREATE INDEX IF NOT EXISTS idx_notifications_archive_user_id 
ON notifications_archive(user_id);

CREATE INDEX IF NOT EXISTS idx_notifications_archive_created_at 
ON notifications_archive(created_at);
