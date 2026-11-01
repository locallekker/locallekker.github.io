-- Diagnostic: Check locallekkerclub@gmail.com admin setup
-- Run this in Supabase SQL Editor

-- 1. Check if user exists and has admin role in profiles
SELECT 
    'PROFILES TABLE' as source,
    id,
    email,
    role,
    CASE 
        WHEN role = 'admin' THEN '✅ Has admin role'
        ELSE '❌ NOT admin role'
    END as status
FROM public.profiles
WHERE email = 'locallekkerclub@gmail.com';

-- 2. Check if user has admin membership
SELECT 
    'MEMBERSHIPS TABLE' as source,
    user_id,
    role,
    CASE 
        WHEN role = 'admin' THEN '✅ Has admin membership'
        ELSE '❌ NOT admin membership'
    END as status
FROM public.memberships
WHERE user_id IN (SELECT id FROM public.profiles WHERE email = 'locallekkerclub@gmail.com');

-- 3. If membership is missing, add it (UNCOMMENT TO FIX):
/*
INSERT INTO public.memberships (user_id, role, created_at, updated_at)
SELECT 
    id,
    'admin',
    NOW(),
    NOW()
FROM public.profiles
WHERE email = 'locallekkerclub@gmail.com'
  AND NOT EXISTS (
    SELECT 1 FROM public.memberships 
    WHERE user_id = profiles.id
  );
*/

-- 4. Verify the fix worked:
SELECT 
    p.email,
    p.role as profile_role,
    m.role as membership_role,
    CASE 
        WHEN p.role = 'admin' AND m.role = 'admin' THEN '✅ FULLY CONFIGURED'
        WHEN p.role = 'admin' AND m.role IS NULL THEN '⚠️ Missing membership entry'
        ELSE '❌ NOT ADMIN'
    END as status
FROM public.profiles p
LEFT JOIN public.memberships m ON m.user_id = p.id
WHERE p.email = 'locallekkerclub@gmail.com';
