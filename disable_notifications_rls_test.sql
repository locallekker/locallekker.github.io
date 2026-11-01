-- =============================================================================
-- FIX NOTIFICATIONS RLS - REMOVE RLS ENTIRELY FOR TESTING
-- =============================================================================
-- This temporarily disables RLS on notifications to confirm it's the issue
-- =============================================================================

-- Disable RLS on notifications table
ALTER TABLE notifications DISABLE ROW LEVEL SECURITY;

-- Verify RLS is disabled
SELECT relname, relrowsecurity, relforcerowsecurity
FROM pg_class
WHERE relname = 'notifications';
