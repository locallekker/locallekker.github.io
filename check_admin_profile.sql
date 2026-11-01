-- Check if admin user exists and has proper profile
-- Run this in Supabase SQL Editor

-- 1. Check if admin exists in auth.users
SELECT 
    id,
    email,
    email_confirmed_at,
    created_at,
    '✅ Admin user exists in auth' as status
FROM auth.users
WHERE email = 'admin@locallekker.com';

-- 2. Check if admin has profile in profiles table
SELECT 
    id,
    email,
    name,
    surname,
    role,
    category,
    created_at,
    '✅ Admin has profile' as status
FROM public.profiles
WHERE email = 'admin@locallekker.com';

-- 3. Check if admin has membership
SELECT 
    user_id,
    role,
    status,
    created_at,
    '✅ Admin has membership' as status
FROM public.memberships
WHERE role = 'admin';

-- 4. Check RLS policies on profiles table
SELECT 
    policyname,
    cmd,
    permissive,
    qual::text as using_clause
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'profiles'
ORDER BY policyname;
