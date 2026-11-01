-- Migration: Check and fix memberships table RLS policies
-- Date: 2025-09-18
-- Description: Check current RLS status on memberships table and fix any recursive policies

BEGIN;

-- Check if RLS is enabled on memberships table
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = 'memberships'
        AND n.nspname = 'public'
        AND c.relrowsecurity = true
    ) THEN
        RAISE NOTICE 'RLS is not enabled on memberships table';
    ELSE
        RAISE NOTICE 'RLS is enabled on memberships table';
    END IF;
END $$;

-- Check existing policies on memberships table
DO $$
DECLARE
    policy_rec record;
BEGIN
    RAISE NOTICE 'Current policies on memberships table:';
    FOR policy_rec IN
        SELECT policyname, permissive, roles, cmd, qual, with_check
        FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'memberships'
    LOOP
        RAISE NOTICE 'Policy: %, Permissive: %, Roles: %, Command: %, Qual: %, With Check: %',
            policy_rec.policyname, policy_rec.permissive, policy_rec.roles,
            policy_rec.cmd, policy_rec.qual, policy_rec.with_check;
    END LOOP;

    IF NOT FOUND THEN
        RAISE NOTICE 'No policies found on memberships table';
    END IF;
END $$;

-- If there are problematic policies, drop them
-- Drop any policies that might cause recursion
DROP POLICY IF EXISTS "Users can view their own memberships" ON public.memberships;
DROP POLICY IF EXISTS "Users can insert their own memberships" ON public.memberships;
DROP POLICY IF EXISTS "Users can update their own memberships" ON public.memberships;
DROP POLICY IF EXISTS "Service role can manage memberships" ON public.memberships;

-- Create safe, non-recursive policies
-- Enable RLS if not already enabled
ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

-- Allow users to view their own memberships
CREATE POLICY "Users can view their own memberships" ON public.memberships
    FOR SELECT
    USING (auth.uid() = user_id);

-- Allow users to insert their own memberships (for role assignment)
CREATE POLICY "Users can insert their own memberships" ON public.memberships
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Allow users to update their own memberships
CREATE POLICY "Users can update their own memberships" ON public.memberships
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Allow service role to manage all memberships (for admin operations)
CREATE POLICY "Service role can manage memberships" ON public.memberships
    FOR ALL
    USING (auth.role() = 'service_role');

COMMIT;