-- Migration: Fix infinite recursion in memberships policies
-- Date: 2024-12-01
-- Issue: Admin policies that check memberships table cause infinite recursion
-- Solution: Use profiles table instead of querying memberships

BEGIN;

-- Drop the problematic admin policies that cause infinite recursion
DROP POLICY IF EXISTS "Admins can view all memberships" ON public.memberships;
DROP POLICY IF EXISTS "Admins can insert any membership" ON public.memberships;
DROP POLICY IF EXISTS "Admins can update any membership" ON public.memberships;
DROP POLICY IF EXISTS "Admins can delete any membership" ON public.memberships;
DROP POLICY IF EXISTS "Admin can view all memberships" ON public.memberships;

-- Recreate admin policies using profiles table to avoid recursion
-- This prevents querying memberships table within memberships policies

-- Allow admins to view all memberships (using profiles)
CREATE POLICY "Admins can view all memberships" ON public.memberships
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- Allow admins to insert memberships for any user (using profiles)
CREATE POLICY "Admins can insert any membership" ON public.memberships
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- Allow admins to update any membership (using profiles)
CREATE POLICY "Admins can update any membership" ON public.memberships
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- Allow admins to delete any membership (using profiles)
CREATE POLICY "Admins can delete any membership" ON public.memberships
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

COMMIT;

-- Verification query (run after migration)
-- SELECT schemaname, tablename, policyname, cmd, qual
-- FROM pg_policies
-- WHERE tablename = 'memberships'
-- ORDER BY policyname;
