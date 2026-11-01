-- Check Admin Permissions for Creating Trusted Partners
-- Run this in Supabase SQL Editor

-- 1. Check profiles table RLS policies (admin needs INSERT permission)
SELECT 
    'PROFILES TABLE' as table_name,
    policyname,
    cmd,
    permissive,
    CASE 
        WHEN cmd = 'INSERT' AND (
            qual::text LIKE '%admin%' OR 
            with_check::text LIKE '%admin%' OR 
            policyname LIKE '%Admins%insert%' OR
            policyname LIKE '%Admins%create%'
        ) THEN '✅ Admin can INSERT'
        WHEN cmd = 'ALL' AND (
            qual::text LIKE '%admin%' OR 
            with_check::text LIKE '%admin%' OR 
            policyname LIKE '%Admins%'
        ) THEN '✅ Admin has ALL access'
        ELSE '⚠️ Check policy'
    END as status,
    qual::text as using_clause,
    with_check::text as with_check_clause
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'profiles'
  AND (cmd IN ('INSERT', 'ALL') OR policyname LIKE '%admin%')
ORDER BY cmd, policyname;

-- 2. Check memberships table RLS policies
SELECT 
    'MEMBERSHIPS TABLE' as table_name,
    policyname,
    cmd,
    permissive,
    CASE 
        WHEN cmd = 'INSERT' AND (
            qual::text LIKE '%admin%' OR 
            with_check::text LIKE '%admin%' OR 
            policyname LIKE '%Admins%insert%' OR
            policyname LIKE '%Admins%create%'
        ) THEN '✅ Admin can INSERT'
        WHEN cmd = 'ALL' AND (
            qual::text LIKE '%admin%' OR 
            with_check::text LIKE '%admin%' OR 
            policyname LIKE '%Admins%'
        ) THEN '✅ Admin has ALL access'
        ELSE '⚠️ Check policy'
    END as status,
    qual::text as using_clause,
    with_check::text as with_check_clause
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'memberships'
  AND (cmd IN ('INSERT', 'ALL') OR policyname LIKE '%admin%')
ORDER BY cmd, policyname;

-- 3. Check businesses table RLS policies
SELECT 
    'BUSINESSES TABLE' as table_name,
    policyname,
    cmd,
    permissive,
    CASE 
        WHEN cmd = 'INSERT' AND (
            qual::text LIKE '%admin%' OR 
            with_check::text LIKE '%admin%' OR 
            policyname LIKE '%Admins%insert%' OR
            policyname LIKE '%Admins%create%'
        ) THEN '✅ Admin can INSERT'
        WHEN cmd = 'ALL' AND (
            qual::text LIKE '%admin%' OR 
            with_check::text LIKE '%admin%' OR 
            policyname LIKE '%Admins%'
        ) THEN '✅ Admin has ALL access'
        ELSE '⚠️ Check policy'
    END as status,
    qual::text as using_clause,
    with_check::text as with_check_clause
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'businesses'
  AND (cmd IN ('INSERT', 'UPDATE', 'ALL') OR policyname LIKE '%admin%')
ORDER BY cmd, policyname;

-- 4. Summary: What permissions does admin have?
SELECT 
    tablename,
    STRING_AGG(DISTINCT cmd::text, ', ' ORDER BY cmd::text) as allowed_operations,
    COUNT(*) as policy_count
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('profiles', 'memberships', 'businesses')
  AND (
    policyname LIKE '%admin%' OR 
    policyname LIKE '%Admin%' OR
    qual::text LIKE '%admin%' OR
    with_check::text LIKE '%admin%'
  )
GROUP BY tablename
ORDER BY tablename;
