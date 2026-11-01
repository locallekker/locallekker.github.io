-- =============================================================================
-- FIX: Allow authenticated users to INSERT notifications
-- =============================================================================
-- Error: "new row violates row-level security policy for table 'notifications'"
-- Cause: No INSERT policy exists for authenticated users
-- Run this in Supabase Dashboard → SQL Editor → New query
-- =============================================================================

-- Drop any existing INSERT policies (clean slate)
DROP POLICY IF EXISTS "Authenticated members can insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "Authenticated can insert notifications for any user" ON public.notifications;
DROP POLICY IF EXISTS "Users can insert own notifications" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_policy" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_authenticated" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_public" ON public.notifications;
DROP POLICY IF EXISTS "Allow authenticated users to create notifications" ON public.notifications;
DROP POLICY IF EXISTS "System can insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_own" ON public.notifications;

-- Create the INSERT policy: any authenticated user can insert notifications
-- This is needed because members notify trusted partners and vice versa
CREATE POLICY "notifications_insert_authenticated" ON public.notifications
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Verify: list all policies on notifications
SELECT policyname, cmd, roles, permissive
FROM pg_policies
WHERE tablename = 'notifications'
ORDER BY cmd, policyname;
