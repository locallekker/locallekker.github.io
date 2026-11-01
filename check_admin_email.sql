-- Check which email is the actual admin account
-- Run this in Supabase SQL Editor

-- 1. Check all users with admin role in profiles
SELECT 
    id,
    email,
    name,
    surname,
    role,
    created_at,
    '✅ Has admin role in profiles' as status
FROM public.profiles
WHERE role = 'admin';

-- 2. Check all users with admin role in memberships
SELECT 
    m.user_id,
    p.email,
    p.name,
    m.role,
    '✅ Has admin role in memberships' as status
FROM public.memberships m
LEFT JOIN public.profiles p ON p.id = m.user_id
WHERE m.role = 'admin';

-- 3. Check if locallekkerclub@gmail.com exists
SELECT 
    id,
    email,
    name,
    surname,
    role,
    created_at
FROM public.profiles
WHERE email = 'locallekkerclub@gmail.com';

-- 4. Check RLS policies on profiles table
SELECT 
    policyname,
    cmd,
    permissive,
    qual::text as using_clause,
    with_check::text as with_check_clause
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'profiles'
ORDER BY policyname;
