-- Diagnose admin UPDATE permissions on businesses table

-- 1. Check what the admin user's role is in profiles table
SELECT 
    id,
    email,
    role,
    CASE 
        WHEN role = 'admin' THEN '✅ User has admin role in profiles'
        ELSE '⚠️ User does NOT have admin role'
    END as admin_status
FROM profiles
WHERE email LIKE '%admin%' OR role = 'admin'
LIMIT 5;

-- 2. Check if admin exists in memberships table with admin role
SELECT 
    user_id,
    role,
    CASE 
        WHEN role = 'admin' THEN '✅ User has admin role in memberships'
        ELSE '⚠️ User does NOT have admin role in memberships'
    END as membership_status
FROM memberships
WHERE role = 'admin'
LIMIT 5;

-- 3. Check alternate admin sources (skip admin_dashboard if not present)
-- Using memberships table as authoritative source for admin role
SELECT 
    user_id,
    role,
    created_at,
    '✅ User has admin role via memberships' as admin_status
FROM memberships
WHERE role = 'admin'
ORDER BY created_at DESC
LIMIT 5;

-- 4. Summary: Which RLS policy check methods exist for admin access
SELECT 
    'Method 1: profiles.role = admin' as check_method,
    COUNT(*) as admin_count
FROM profiles
WHERE role = 'admin'

UNION ALL

SELECT 
    'Method 2: memberships.role = admin' as check_method,
    COUNT(*) as admin_count
FROM memberships
WHERE role = 'admin';

-- 5. Test UPDATE permission simulation
-- This shows if the RLS policy would allow the UPDATE
SELECT 
    'Testing admin UPDATE on businesses' as test_description,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM profiles 
            WHERE role = 'admin' 
            LIMIT 1
        ) THEN '✅ Admin role exists in profiles (RLS will pass if policy checks profiles.role)'
        ELSE '❌ No admin in profiles table'
    END as profiles_check,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM memberships 
            WHERE role = 'admin' 
            LIMIT 1
        ) THEN '✅ Admin role exists in memberships (RLS will pass if policy checks memberships.role)'
        ELSE '❌ No admin in memberships table'
    END as memberships_check;

-- 6. List active businesses RLS policies relevant to UPDATE
SELECT 
    policyname,
    cmd,
    roles,
    qual::text as using_expression,
    with_check::text as with_check_expression
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'businesses'
  AND cmd IN ('UPDATE','ALL')
ORDER BY policyname;
