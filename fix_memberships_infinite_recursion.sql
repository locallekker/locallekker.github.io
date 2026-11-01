-- Fix Infinite Recursion in Memberships RLS Policy
-- The issue is the admin policy checks memberships table while querying it

-- Drop the problematic policy
DROP POLICY IF EXISTS "Admins can view all memberships" ON public.memberships;

-- Create a new admin policy that checks the profile role instead
CREATE POLICY "Admins can view all memberships" ON public.memberships
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- Verify the fix
SELECT schemaname, tablename, policyname, permissive, roles, cmd
FROM pg_policies
WHERE tablename = 'memberships' AND policyname = 'Admins can view all memberships';

-- Test query - should work without infinite recursion error
SELECT user_id, role, gateway, created_at
FROM public.memberships
WHERE role = 'trusted_partner'
ORDER BY created_at DESC;
