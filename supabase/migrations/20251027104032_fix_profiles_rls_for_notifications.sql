-- =============================================================================
-- FIX PROFILES RLS POLICY FOR CROSS-USER NOTIFICATIONS
-- Migration: 20251027104032_fix_profiles_rls_for_notifications
-- =============================================================================
-- The profiles table RLS policies prevent foreign key validation when
-- creating notifications for other users (trusted partners).
-- This fix allows authenticated users to SELECT profiles for FK validation.
-- =============================================================================

-- Drop the restrictive SELECT policy
DROP POLICY IF EXISTS "Members can view their own profile" ON profiles;

-- Create a new policy that allows authenticated users to SELECT profiles
-- This is needed for foreign key validation in notifications and other tables
CREATE POLICY "Authenticated users can view profiles for FK validation" ON profiles
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- Keep the other policies for UPDATE and INSERT (users can only modify their own)
-- UPDATE policy (already exists)
-- INSERT policy (already exists)

-- Verify the new policy
SELECT
    schemaname,
    tablename,
    policyname,
    cmd,
    qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'profiles'
ORDER BY cmd, policyname;