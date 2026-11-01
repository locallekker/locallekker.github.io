-- Fix for thecraftsmanel@gmail.com - user exists and email is confirmed
-- Run this in Supabase SQL Editor

-- 1. Check the user's complete profile status (separate queries to avoid type mismatch)
SELECT '=== AUTH.USERS STATUS ===' as section;
SELECT id, email, email_confirmed_at, created_at
FROM auth.users
WHERE email = 'thecraftsmanel@gmail.com';

SELECT '=== PROFILES STATUS ===' as section;
SELECT id, email, email_verified, password_set, admin_created, role, created_at
FROM profiles
WHERE email = 'thecraftsmanel@gmail.com';

SELECT '=== TRUSTED_PARTNERS STATUS ===' as section;
SELECT tp.user_id, tp.business_name, tp.created_at
FROM trusted_partners tp
JOIN profiles p ON tp.user_id = p.id
WHERE p.email = 'thecraftsmanel@gmail.com';

-- 2. Check if the user has password_set = true in profiles
SELECT 'Password status check:' as check;

SELECT
    p.id,
    p.email,
    p.password_set,
    p.admin_created,
    p.role
FROM profiles p
WHERE p.email = 'thecraftsmanel@gmail.com';

-- 3. If password_set is false, set it to true so they can log in
-- Uncomment this if the user should be able to log in normally:
/*
UPDATE profiles
SET password_set = true, updated_at = NOW()
WHERE email = 'thecraftsmanel@gmail.com';
*/

-- 4. If the user is getting password reset emails when they should be able to log in,
-- the issue is in the app logic that checks admin_created/password_set status

-- 5. Alternative: If the user needs to actually reset their password,
-- they should use the password reset flow in the app