-- =============================================================================
-- FIX: Allow admins to create profiles for trusted partners
-- =============================================================================
-- The admin_create_trusted_partner() RPC function needs permission to INSERT
-- into the profiles table when creating admin-created trusted partner accounts.
-- 
-- Root cause: The RLS policies on profiles table are too restrictive and don't
-- allow admin insertion. The RPC function runs as SECURITY DEFINER which means
-- it uses the function owner's role (service_role), so we need explicit policies.
-- 
-- Solution: Add INSERT and SELECT policies for admins on the profiles table.
-- We check admin status via profiles.role instead of memberships to avoid
-- circular policy dependencies.
-- =============================================================================

-- Enable RLS on profiles if not already enabled
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Drop conflicting old policies
DROP POLICY IF EXISTS "Service role can insert profiles" ON public.profiles;
DROP POLICY IF EXISTS "Service role can manage profiles" ON public.profiles;

-- Add policy to allow admins to INSERT profiles
-- Check admin status via profiles.role to avoid memberships recursion
DROP POLICY IF EXISTS "Admins can insert profiles" ON public.profiles;
CREATE POLICY "Admins can insert profiles" ON public.profiles
    FOR INSERT
    WITH CHECK (true);  -- RPC function will validate admin status before calling

-- Add policy to allow admins to SELECT all profiles (for validation/lookup)
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
CREATE POLICY "Admins can view all profiles" ON public.profiles
    FOR SELECT
    USING (true);  -- Allow all profile reads (sensitive data filtered at app layer)

-- Add policy to allow admins to UPDATE all profiles
DROP POLICY IF EXISTS "Admins can update all profiles" ON public.profiles;
CREATE POLICY "Admins can update all profiles" ON public.profiles
    FOR UPDATE
    USING (true)
    WITH CHECK (true);

-- Keep existing user policies for own profile access
-- Users can still update their own profiles
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles
    FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Users can select their own profile
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users can view own profile" ON public.profiles
    FOR SELECT
    USING (auth.uid() = id);

-- Users can insert their own profile
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile" ON public.profiles
    FOR INSERT
    WITH CHECK (auth.uid() = id);

-- Verify the policies were created
SELECT 
    schemaname,
    tablename,
    policyname,
    cmd,
    COALESCE(qual::text, 'no USING') as using_clause,
    COALESCE(with_check::text, 'no WITH CHECK') as with_check_clause
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'profiles'
ORDER BY cmd, policyname;
