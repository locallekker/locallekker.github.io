-- Update admin RLS policies to include locallekkerclub@gmail.com
-- Run this in Supabase SQL Editor

-- Drop existing admin policies
DROP POLICY IF EXISTS "admin_profiles_access" ON public.profiles;
DROP POLICY IF EXISTS "admin_memberships_access" ON public.memberships;

-- Recreate admin policies with correct admin emails
CREATE POLICY "admin_profiles_access" ON public.profiles
FOR ALL USING (
  auth.jwt() ->> 'email' IN ('admin@locallekker.com', 'locallekkerclub@gmail.com', 'clydemflan@gmail.com')
);

CREATE POLICY "admin_memberships_access" ON public.memberships
FOR ALL USING (
  auth.jwt() ->> 'email' IN ('admin@locallekker.com', 'locallekkerclub@gmail.com', 'clydemflan@gmail.com')
);

-- Verify the policies were created
SELECT 
    policyname,
    cmd,
    permissive,
    qual::text as using_clause
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('profiles', 'memberships')
  AND policyname LIKE '%admin%'
ORDER BY tablename, policyname;
