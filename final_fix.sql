-- Final fix for thecraftsmanel@gmail.com
-- Run this in Supabase SQL Editor

-- Based on the password_set status you found, run the appropriate fix:

-- IF password_set = false, run this to allow normal login:
UPDATE profiles
SET password_set = true, updated_at = NOW()
WHERE email = 'thecraftsmanel@gmail.com';

-- IF password_set = true but user still gets password reset emails,
-- the issue is in the app's login flow logic

-- Verify the fix worked:
SELECT
    p.email,
    p.password_set,
    p.admin_created,
    p.role,
    au.email_confirmed_at
FROM profiles p
JOIN auth.users au ON au.id = p.id
WHERE p.email = 'thecraftsmanel@gmail.com';