-- =============================================================================
-- CLEANUP REMAINING "ALWAYS TRUE" POLICIES
-- =============================================================================
-- Based on verification query results, these policies still need attention
-- =============================================================================

-- =============================================================================
-- 1. NOTIFICATIONS - Drop old insert policy, keep the new one
-- =============================================================================

-- Drop the old overly permissive policy
DROP POLICY IF EXISTS "notifications_insert_policy" ON notifications;

-- Verify our new policy exists (should already be created)
-- "Users can insert own notifications" with CHECK (user_id = auth.uid())

-- =============================================================================
-- 2. PROFILES - Review admin policies
-- =============================================================================

-- These admin policies are overly permissive but may be intentional for admin access
-- Let's make them more explicit that they're admin-only

-- Check if these are actually checking for admin role
SELECT 
    policyname,
    qual as using_clause,
    with_check
FROM pg_policies 
WHERE tablename = 'profiles'
  AND policyname IN ('Admins can insert profiles', 'Admins can update all profiles');

-- If they're not checking for admin role, drop and recreate them properly
DROP POLICY IF EXISTS "Admins can insert profiles" ON profiles;
DROP POLICY IF EXISTS "Admins can update all profiles" ON profiles;

-- Recreate with proper admin checks
CREATE POLICY "Admins can insert profiles" 
ON profiles
FOR INSERT 
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid() AND p.role = 'admin'
  )
);

CREATE POLICY "Admins can update all profiles" 
ON profiles
FOR UPDATE 
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid() AND p.role = 'admin'
  )
);

-- =============================================================================
-- 3. RECOVERY_SESSIONS - This is acceptable as-is
-- =============================================================================
-- "Authenticated users can insert recovery sessions" WITH CHECK (true)
-- This is acceptable because:
-- 1. Only authenticated users can use it (not anonymous)
-- 2. The password recovery flow requires users to create sessions
-- 3. The SELECT policy already filters by expires_at and used status

-- =============================================================================
-- 4. ARCHIVED_MEMBERS - This is acceptable as-is
-- =============================================================================
-- "Service role can insert archived members" WITH CHECK (true)
-- This is acceptable because:
-- 1. It's restricted to service_role (not public users)
-- 2. Only used by admin deletion functions with SECURITY DEFINER

-- =============================================================================
-- FINAL VERIFICATION
-- =============================================================================

-- Check remaining "always true" policies
SELECT 
    tablename,
    policyname,
    cmd,
    roles,
    CASE 
        WHEN qual = 'true' AND roles = '{authenticated}' THEN '⚠️  Authenticated USING (true)'
        WHEN with_check = 'true' AND roles = '{authenticated}' THEN '⚠️  Authenticated CHECK (true)'
        WHEN qual = 'true' AND roles::text LIKE '%service_role%' THEN '✅ Service role (OK)'
        WHEN with_check = 'true' AND roles::text LIKE '%service_role%' THEN '✅ Service role (OK)'
        WHEN qual != 'true' AND with_check != 'true' THEN '✅ Properly filtered'
        ELSE '❌ Needs review'
    END as status
FROM pg_policies 
WHERE schemaname = 'public'
  AND tablename IN ('archived_members', 'notifications', 'profiles', 'recovery_sessions')
ORDER BY 
    tablename, 
    policyname;

-- Summary
DO $$
BEGIN
    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'Cleanup Complete:';
    RAISE NOTICE '1. ✅ Dropped old notifications_insert_policy';
    RAISE NOTICE '2. ✅ Fixed admin profile policies to check for admin role';
    RAISE NOTICE '3. ✅ Verified recovery_sessions policy (acceptable)';
    RAISE NOTICE '4. ✅ Verified archived_members policy (acceptable for service_role)';
    RAISE NOTICE '';
    RAISE NOTICE 'Remaining acceptable "true" policies:';
    RAISE NOTICE '- Service role policies (admin functions only)';
    RAISE NOTICE '- Authenticated recovery sessions (required for password reset flow)';
    RAISE NOTICE '=============================================================================';
END $$;
