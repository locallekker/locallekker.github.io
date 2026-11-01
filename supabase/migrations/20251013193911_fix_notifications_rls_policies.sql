-- =============================================================================
-- FIX NOTIFICATIONS RLS POLICIES
-- =============================================================================
-- Issue: Conflicting RLS policies prevent deal authorization notifications
-- The "FOR ALL" policy restricts inserts to user_id = auth.uid(), but the app
-- needs to allow authenticated users to create notifications for other users
-- (e.g., members creating notifications for trusted partners)

-- Drop conflicting policies
DROP POLICY IF EXISTS "Users can view their own notifications" ON notifications;
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON notifications;
DROP POLICY IF EXISTS "Users can update their notifications" ON notifications;

-- Create proper policies
CREATE POLICY "Users can view their notifications" ON notifications
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Authenticated users can insert notifications" ON notifications
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Users can update their notifications" ON notifications
    FOR UPDATE USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());