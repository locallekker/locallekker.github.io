-- =============================================================================
-- FINAL RLS POLICY REFINEMENTS
-- =============================================================================
-- Address remaining overly permissive policies
-- =============================================================================

-- 1. Fix "Anonymous can check profile existence" - Too broad
-- This allows anonymous users to potentially enumerate all profiles
DROP POLICY IF EXISTS "Anonymous can check profile existence" ON profiles;

-- Anonymous users should ONLY use the check_email_exists() RPC function
-- No direct anonymous SELECT access to profiles table needed

-- 2. Verify archived_members policy roles
-- "Service role can insert archived members" should be for service_role, not public
-- If it shows {public}, we need to recreate it

-- Check current archived_members policies
SELECT 
    policyname, 
    cmd, 
    roles::text,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'archived_members';

-- If needed, recreate service_role policy properly
DROP POLICY IF EXISTS "Service role can insert archived members" ON archived_members;

CREATE POLICY "Service role can insert archived members" 
ON archived_members
FOR INSERT 
TO service_role
WITH CHECK (true);  -- Service role can insert anything (admin deletion function)

-- =============================================================================
-- VERIFICATION: Check for remaining "USING (true)" warnings
-- =============================================================================

-- Find policies that Security Advisor will flag
SELECT 
    tablename,
    policyname,
    cmd,
    roles::text as role_list,
    CASE 
        WHEN qual::text = 'true' AND roles != '{service_role}' THEN '⚠️ USING (true) - Public/Auth'
        WHEN with_check::text = 'true' AND roles != '{service_role}' THEN '⚠️ WITH CHECK (true) - Public/Auth'
        WHEN qual::text = 'true' AND roles = '{service_role}' THEN '✅ Service role (OK)'
        WHEN with_check::text = 'true' AND roles = '{service_role}' THEN '✅ Service role (OK)'
        ELSE '✅ Properly filtered'
    END as security_status
FROM pg_policies 
WHERE schemaname = 'public'
  AND tablename IN ('archived_members', 'notifications', 'profiles', 'recovery_sessions')
  AND (qual::text = 'true' OR with_check::text = 'true')
ORDER BY tablename, policyname;

-- Expected acceptable "true" policies:
-- 1. Service role policies (archived_members insert)
-- 2. Authenticated recovery sessions insert (password reset flow)

-- Summary
DO $$
DECLARE
    warning_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO warning_count
    FROM pg_policies 
    WHERE schemaname = 'public'
      AND tablename IN ('archived_members', 'notifications', 'profiles', 'recovery_sessions')
      AND (qual::text = 'true' OR with_check::text = 'true')
      AND roles != '{service_role}'
      AND NOT (tablename = 'recovery_sessions' AND cmd = 'INSERT' AND roles = '{authenticated}');
    
    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'Final Refinements Complete';
    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'Remaining overly permissive policies: %', warning_count;
    RAISE NOTICE '';
    RAISE NOTICE 'Acceptable exceptions:';
    RAISE NOTICE '- Service role policies (system functions)';
    RAISE NOTICE '- Recovery sessions INSERT (password reset flow)';
    RAISE NOTICE '=============================================================================';
    
    IF warning_count = 0 THEN
        RAISE NOTICE '✅ All RLS policy warnings should now be resolved!';
    ELSE
        RAISE NOTICE '⚠️ Review Security Advisor for remaining warnings';
    END IF;
    
    RAISE NOTICE '=============================================================================';
END $$;
