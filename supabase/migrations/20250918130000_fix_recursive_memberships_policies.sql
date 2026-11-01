-- Migration: Fix recursive policies on memberships table
-- Date: 2025-09-18
-- Description: Remove recursive policies that cause infinite recursion

BEGIN;

-- Drop the problematic recursive policies
DROP POLICY IF EXISTS "Admins can read all memberships" ON public.memberships;
DROP POLICY IF EXISTS "admin_all" ON public.memberships;

-- Create safe, non-recursive policies (only if they don't exist)
DO $$
BEGIN
    -- Check and create SELECT policy
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'memberships' AND policyname = 'Users can view their own memberships'
    ) THEN
        CREATE POLICY "Users can view their own memberships" ON public.memberships
            FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    -- Check and create INSERT policy
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'memberships' AND policyname = 'Users can insert their own memberships'
    ) THEN
        CREATE POLICY "Users can insert their own memberships" ON public.memberships
            FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;

    -- Check and create UPDATE policy
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'memberships' AND policyname = 'Users can update their own memberships'
    ) THEN
        CREATE POLICY "Users can update their own memberships" ON public.memberships
            FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;

    -- Check and create service role policy
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'memberships' AND policyname = 'Service role can manage memberships'
    ) THEN
        CREATE POLICY "Service role can manage memberships" ON public.memberships
            FOR ALL
            USING (auth.role() = 'service_role');
    END IF;
END $$;

COMMIT;