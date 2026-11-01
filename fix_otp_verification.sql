-- Fix OTP verification issue for thecraftsmanel@gmail.com
-- Run this in Supabase SQL Editor

-- 1. Check if the user exists in auth.users
SELECT 'Checking thecraftsmanel@gmail.com in auth.users:' as check;

SELECT id, email, email_confirmed_at, created_at, last_sign_in_at
FROM auth.users
WHERE email = 'thecraftsmanel@gmail.com';

-- 2. Check the user's profile status
SELECT 'Checking thecraftsmanel@gmail.com profile:' as check;

SELECT p.id, p.email, p.role, p.admin_created, p.password_set, p.email_verified
FROM profiles p
WHERE p.email = 'thecraftsmanel@gmail.com';

-- 3. If user exists in auth.users but email_confirmed_at is NULL,
-- they need to verify their email. The issue might be that the wrong OTP type is being used.

-- Option A: If the user needs to complete signup verification
-- (they received signup OTP but haven't verified it yet)
-- The app should call verifyOtp with isForSignIn: false

-- Option B: If the user already exists and is getting password reset emails,
-- they might need to use the password reset flow instead

-- Option C: Delete the auth user and recreate them properly
-- Uncomment these lines if you want to start fresh:
/*
-- First, get the user ID from auth.users
-- Then delete from auth.users (requires admin privileges)
-- Then the admin can recreate the trusted partner
*/

-- 4. Alternative: Force email verification for this user
-- Uncomment to mark email as verified (if appropriate):
/*
UPDATE auth.users
SET email_confirmed_at = NOW()
WHERE email = 'thecraftsmanel@gmail.com'
AND email_confirmed_at IS NULL;
*/

-- 5. Check what OTP type should be used
-- If email_confirmed_at IS NULL: Use OtpType.signup for verification
-- If email_confirmed_at IS NOT NULL: Use OtpType.email for sign-in or password reset