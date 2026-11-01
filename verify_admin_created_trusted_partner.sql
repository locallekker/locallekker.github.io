-- Verification Script: Admin-Created Trusted Partner Setup
-- Purpose: Verify that admin-created trusted partner accounts are set up correctly
-- Usage: Replace 'test@example.com' with the actual email to verify
-- Run this in Supabase SQL Editor after creating a trusted partner via admin

-- =====================================================
-- CONFIGURATION: Change this to the email you created
-- =====================================================
-- SELECT email, id FROM auth.users WHERE email = 'test@example.com';

-- =====================================================
-- 1. CHECK AUTH.USERS TABLE
-- =====================================================
WRITE 'Step 1: Checking auth.users table...';

SELECT 
    id,
    email,
    email_confirmed_at,
    raw_user_meta_data->'user_type' as user_type,
    raw_user_meta_data->'admin_created' as admin_created,
    raw_user_meta_data->'password_set' as password_set,
    raw_user_meta_data->'email_verified' as email_verified,
    raw_user_meta_data->'name' as name,
    raw_user_meta_data->'surname' as surname,
    created_at
FROM auth.users 
WHERE email = 'test@example.com'
LIMIT 1;

-- =====================================================
-- 2. CHECK PROFILES TABLE
-- =====================================================
WRITE 'Step 2: Checking profiles table...';

SELECT 
    id,
    email,
    name,
    surname,
    role,
    admin_created,
    password_set,
    email_verified,
    created_at
FROM public.profiles
WHERE email = 'test@example.com'
LIMIT 1;

-- =====================================================
-- 3. CHECK MEMBERSHIPS TABLE
-- =====================================================
WRITE 'Step 3: Checking memberships table...';

SELECT 
    id,
    user_id,
    role,
    status,
    created_at
FROM public.memberships
WHERE user_id IN (
    SELECT id FROM auth.users WHERE email = 'test@example.com'
)
LIMIT 1;

-- =====================================================
-- 4. CHECK TRUSTED_PARTNERS TABLE
-- =====================================================
WRITE 'Step 4: Checking trusted_partners table...';

SELECT 
    id,
    user_id,
    business_name,
    unique_key,
    created_at
FROM public.trusted_partners
WHERE user_id IN (
    SELECT id FROM auth.users WHERE email = 'test@example.com'
)
LIMIT 1;

-- =====================================================
-- 5. CHECK BUSINESSES TABLE
-- =====================================================
WRITE 'Step 5: Checking businesses table...';

SELECT 
    id,
    name,
    owner_member_id,
    category,
    allow_admin_deal_creation,
    created_at
FROM public.businesses
WHERE owner_member_id IN (
    SELECT id FROM auth.users WHERE email = 'test@example.com'
)
LIMIT 1;

-- =====================================================
-- 6. CHECK USER_QR_CODES TABLE
-- =====================================================
WRITE 'Step 6: Checking user_qr_codes table...';

SELECT 
    id,
    user_id,
    qr_code,
    qr_code_url,
    expires_at,
    created_at
FROM public.user_qr_codes
WHERE user_id IN (
    SELECT id FROM auth.users WHERE email = 'test@example.com'
)
LIMIT 1;

-- =====================================================
-- 7. VERIFICATION SUMMARY
-- =====================================================
WRITE 'Step 7: Verification Summary...';

WITH user_check AS (
    SELECT 
        id,
        email,
        CASE WHEN email_confirmed_at IS NOT NULL THEN 'PASS' ELSE 'FAIL' END as email_confirmed,
        CASE WHEN raw_user_meta_data->>'user_type' = 'trusted_partner' THEN 'PASS' ELSE 'FAIL' END as user_type_correct,
        CASE WHEN raw_user_meta_data->>'admin_created' = 'true' THEN 'PASS' ELSE 'FAIL' END as admin_created_flag,
        CASE WHEN raw_user_meta_data->>'password_set' = 'true' THEN 'PASS' ELSE 'FAIL' END as password_set_flag
    FROM auth.users
    WHERE email = 'test@example.com'
),
profile_check AS (
    SELECT 
        CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END as profile_exists,
        CASE WHEN MAX(role) = 'trusted_partner' THEN 'PASS' ELSE 'FAIL' END as role_correct
    FROM public.profiles
    WHERE email = 'test@example.com'
),
membership_check AS (
    SELECT 
        CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END as membership_exists,
        CASE WHEN MAX(role) = 'trusted_partner' THEN 'PASS' ELSE 'FAIL' END as membership_role_correct
    FROM public.memberships
    WHERE user_id IN (SELECT id FROM user_check)
),
tp_check AS (
    SELECT 
        CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END as tp_record_exists
    FROM public.trusted_partners
    WHERE user_id IN (SELECT id FROM user_check)
),
business_check AS (
    SELECT 
        CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'FAIL' END as business_exists
    FROM public.businesses
    WHERE owner_member_id IN (SELECT id FROM user_check)
),
qr_check AS (
    SELECT 
        CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'FAIL' END as qr_code_exists
    FROM public.user_qr_codes
    WHERE user_id IN (SELECT id FROM user_check)
)
SELECT 
    'Auth User Confirmed' as check_item,
    (SELECT email_confirmed FROM user_check) as result
UNION ALL
SELECT 'Auth User Type Correct', (SELECT user_type_correct FROM user_check)
UNION ALL
SELECT 'Admin Created Flag Set', (SELECT admin_created_flag FROM user_check)
UNION ALL
SELECT 'Password Set Flag', (SELECT password_set_flag FROM user_check)
UNION ALL
SELECT 'Profile Exists', (SELECT profile_exists FROM profile_check)
UNION ALL
SELECT 'Profile Role Correct', (SELECT role_correct FROM profile_check)
UNION ALL
SELECT 'Membership Exists', (SELECT membership_exists FROM membership_check)
UNION ALL
SELECT 'Membership Role Correct', (SELECT membership_role_correct FROM membership_check)
UNION ALL
SELECT 'Trusted Partner Record Exists', (SELECT tp_record_exists FROM tp_check)
UNION ALL
SELECT 'Business Record Exists', (SELECT business_exists FROM business_check)
UNION ALL
SELECT 'QR Code Generated', (SELECT qr_code_exists FROM qr_check);

-- =====================================================
-- 8. COMPARISON: Metadata Consistency
-- =====================================================
WRITE 'Step 8: Metadata Consistency Check...';

SELECT 
    au.email,
    au.raw_user_meta_data->>'user_type' as auth_user_type,
    p.role as profile_role,
    CASE 
        WHEN (au.raw_user_meta_data->>'user_type')::text = 'trusted_partner' 
             AND p.role = 'trusted_partner' 
        THEN 'PASS: Role is consistent'
        ELSE 'FAIL: Role mismatch'
    END as role_consistency,
    CASE 
        WHEN au.email_confirmed_at IS NOT NULL 
        THEN 'PASS: Email verified, OTP skipped'
        ELSE 'FAIL: Email not verified'
    END as email_verification_status
FROM auth.users au
LEFT JOIN public.profiles p ON au.id = p.id
WHERE au.email = 'test@example.com';

-- =====================================================
-- 9. CHECK FOR ORPHANED RECORDS
-- =====================================================
WRITE 'Step 9: Checking for orphaned records...';

SELECT 
    'Profiles without auth user' as orphan_type,
    COUNT(*) as count
FROM public.profiles p
WHERE p.id NOT IN (SELECT id FROM auth.users)
  AND p.email = 'test@example.com'
UNION ALL
SELECT 
    'Memberships without profile',
    COUNT(*)
FROM public.memberships m
WHERE m.user_id NOT IN (SELECT id FROM public.profiles)
  AND m.user_id IN (SELECT id FROM auth.users WHERE email = 'test@example.com')
UNION ALL
SELECT 
    'Trusted partners without profile',
    COUNT(*)
FROM public.trusted_partners tp
WHERE tp.user_id NOT IN (SELECT id FROM public.profiles)
  AND tp.user_id IN (SELECT id FROM auth.users WHERE email = 'test@example.com')
UNION ALL
SELECT 
    'Businesses without owner profile',
    COUNT(*)
FROM public.businesses b
WHERE b.owner_member_id NOT IN (SELECT id FROM public.profiles)
  AND b.owner_member_id IN (SELECT id FROM auth.users WHERE email = 'test@example.com');

-- =====================================================
-- 10. FINAL RESULT
-- =====================================================
WRITE 'Step 10: Final Result...';

WITH all_checks AS (
    SELECT 
        CASE 
            WHEN EXISTS (SELECT 1 FROM auth.users WHERE email = 'test@example.com')
              AND EXISTS (SELECT 1 FROM public.profiles WHERE email = 'test@example.com')
              AND EXISTS (SELECT 1 FROM public.memberships WHERE user_id IN (SELECT id FROM auth.users WHERE email = 'test@example.com'))
              AND EXISTS (SELECT 1 FROM public.trusted_partners WHERE user_id IN (SELECT id FROM auth.users WHERE email = 'test@example.com'))
              AND EXISTS (SELECT 1 FROM public.user_qr_codes WHERE user_id IN (SELECT id FROM auth.users WHERE email = 'test@example.com'))
            THEN '✅ SUCCESS: All records created correctly'
            ELSE '❌ FAILURE: Some records are missing'
        END as final_status
)
SELECT final_status FROM all_checks;
