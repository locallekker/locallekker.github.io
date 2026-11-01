-- Complete SQL Migration for Deal Image Upload Fix
-- Run this in Supabase SQL Editor
-- This fixes broken RLS policies and verifies admin permissions

-- ============================================================================
-- PART 1: Fix Broken Deal Image INSERT Policies
-- ============================================================================

BEGIN;

-- Drop the broken INSERT policies (they have null WITH CHECK)
DROP POLICY IF EXISTS "Admins can upload deal images for authorized partners" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can upload deal images" ON storage.objects;

-- Recreate admin INSERT policy with proper WITH CHECK
CREATE POLICY "Admins can upload deal images for authorized partners" 
ON storage.objects
FOR INSERT 
WITH CHECK (
    bucket_id = 'business-bills' AND
    name LIKE 'deal_images/%' AND
    -- Check user is admin via memberships
    EXISTS (
        SELECT 1
        FROM public.memberships m
        WHERE m.user_id = auth.uid()
          AND m.role = 'admin'
    ) AND
    -- Check business allows admin deal creation
    EXISTS (
        SELECT 1
        FROM public.businesses b
        WHERE b.owner_member_id::text = split_part(name, '/', 2)
          AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
);

-- Recreate trusted partner INSERT policy with proper WITH CHECK
CREATE POLICY "Trusted partners can upload deal images" 
ON storage.objects
FOR INSERT 
WITH CHECK (
    bucket_id = 'business-bills' AND
    name LIKE 'deal_images/%' AND
    split_part(name, '/', 2) = auth.uid()::text
);

COMMIT;

-- ============================================================================
-- PART 2: Verify Admin Exists in Memberships Table
-- ============================================================================

-- Check if admin user exists in memberships with admin role
SELECT 
    user_id,
    role,
    created_at,
    '✅ Admin can upload deal images' as status
FROM memberships
WHERE role = 'admin';

-- If above returns 0 rows, admin needs to be added to memberships
-- Uncomment and run this if needed:

-- INSERT INTO memberships (user_id, role, created_at)
-- SELECT id, 'admin', NOW()
-- FROM profiles
-- WHERE role = 'admin'
--   AND id NOT IN (SELECT user_id FROM memberships WHERE role = 'admin');

-- ============================================================================
-- PART 3: Enable Admin Deal Creation for That Old Oak
-- ============================================================================

-- Check current status
SELECT 
    name,
    owner_member_id,
    allow_admin_deal_creation,
    CASE 
        WHEN allow_admin_deal_creation = true THEN '✅ Admin CAN create deals'
        ELSE '❌ Admin CANNOT create deals - need to enable'
    END as admin_permission
FROM businesses
WHERE owner_member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- If above shows false, enable it:
-- Uncomment and run this if needed:

-- UPDATE businesses
-- SET allow_admin_deal_creation = true
-- WHERE owner_member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- ============================================================================
-- PART 4: Verify Fixes Applied Successfully
-- ============================================================================

-- Check INSERT policies now have WITH CHECK clauses
SELECT 
    policyname,
    cmd,
    with_check::text as with_check_expression,
    CASE 
        WHEN cmd = 'INSERT' AND with_check IS NOT NULL THEN '✅ Has WITH CHECK'
        WHEN cmd = 'INSERT' AND with_check IS NULL THEN '❌ Missing WITH CHECK'
        ELSE 'N/A (not INSERT)'
    END as policy_status
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND policyname IN (
    'Admins can upload deal images for authorized partners',
    'Trusted partners can upload deal images'
  )
ORDER BY policyname;

-- Final summary
SELECT 
    '1. RLS policies fixed' as check_item,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_policies
            WHERE schemaname = 'storage'
              AND tablename = 'objects'
              AND policyname = 'Admins can upload deal images for authorized partners'
              AND with_check IS NOT NULL
        ) THEN '✅ Complete'
        ELSE '❌ Failed'
    END as status

UNION ALL

SELECT 
    '2. Admin in memberships' as check_item,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM memberships WHERE role = 'admin'
        ) THEN '✅ Complete'
        ELSE '⚠️ Need to add admin to memberships'
    END as status

UNION ALL

SELECT 
    '3. That Old Oak allows admin deals' as check_item,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM businesses 
            WHERE owner_member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
              AND allow_admin_deal_creation = true
        ) THEN '✅ Complete'
        ELSE '⚠️ Need to enable allow_admin_deal_creation'
    END as status;
