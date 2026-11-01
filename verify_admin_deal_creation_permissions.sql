-- Verification SQL for Admin Deal Creation on Behalf of Trusted Partners
-- Run this in Supabase SQL Editor to verify admin permissions

-- ============================================================================
-- 1. CHECK BUSINESSES TABLE - allow_admin_deal_creation COLUMN
-- ============================================================================
SELECT 
    '1. BUSINESSES TABLE - ADMIN PERMISSION COLUMN' as check_section,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = 'businesses' 
              AND column_name = 'allow_admin_deal_creation'
        ) 
        THEN '✅ allow_admin_deal_creation column EXISTS'
        ELSE '❌ ERROR: allow_admin_deal_creation column MISSING - need to add it'
    END as result,
    (SELECT data_type FROM information_schema.columns 
     WHERE table_schema = 'public' AND table_name = 'businesses' 
       AND column_name = 'allow_admin_deal_creation') as column_type,
    (SELECT column_default FROM information_schema.columns 
     WHERE table_schema = 'public' AND table_name = 'businesses' 
       AND column_name = 'allow_admin_deal_creation') as default_value;

-- ============================================================================
-- 2. CHECK WHICH BUSINESSES ALLOW ADMIN DEAL CREATION
-- ============================================================================
SELECT 
    '2. BUSINESSES ALLOWING ADMIN DEAL CREATION' as check_section,
    id,
    name,
    owner_member_id,
    COALESCE(allow_admin_deal_creation, false) as allow_admin_deal_creation,
    CASE 
        WHEN COALESCE(allow_admin_deal_creation, false) = true 
        THEN '✅ Admin CAN create deals'
        ELSE '⚠️ Admin CANNOT create deals (toggle in Business Profile)'
    END as status
FROM businesses
ORDER BY created_at DESC
LIMIT 10;

-- ============================================================================
-- 3. CHECK RLS POLICIES ON trusted_partner_discounts TABLE
-- ============================================================================
SELECT 
    '3. TRUSTED_PARTNER_DISCOUNTS RLS POLICIES' as check_section,
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    CASE 
        WHEN policyname ILIKE '%admin%' AND cmd = 'INSERT' 
        THEN '✅ Admin INSERT policy exists'
        WHEN policyname ILIKE '%admin%' 
        THEN '✓ Admin policy (not INSERT)'
        WHEN cmd = 'INSERT' 
        THEN '⚠️ INSERT policy (not admin-specific)'
        ELSE '✓ Other policy'
    END as relevance,
    CASE 
        WHEN qual ILIKE '%admin_dashboard%' THEN 'Uses admin_dashboard table'
        WHEN qual ILIKE '%profiles%' AND qual ILIKE '%role%' AND qual ILIKE '%admin%' THEN 'Uses profiles.role = admin'
        ELSE 'Other logic'
    END as admin_check_method
FROM pg_policies
WHERE schemaname = 'public' 
  AND tablename = 'trusted_partner_discounts'
ORDER BY policyname;

-- ============================================================================
-- 4. CHECK STORAGE POLICIES FOR DEAL IMAGE UPLOADS
-- ============================================================================
SELECT 
    '4. STORAGE POLICIES - business-bills BUCKET' as check_section,
    schemaname,
    tablename,
    policyname,
    permissive,
    cmd,
    CASE 
        WHEN policyname ILIKE '%admin%' AND policyname ILIKE '%deal%' AND cmd = 'INSERT' 
        THEN '✅ Admin can upload deal images'
        WHEN policyname ILIKE '%admin%' AND cmd = 'INSERT' 
        THEN '✓ Admin INSERT policy exists'
        WHEN policyname ILIKE '%deal%' AND cmd = 'INSERT' 
        THEN '⚠️ Deal image policy (check if admin-compatible)'
        ELSE '✓ Other storage policy'
    END as relevance,
    CASE 
        WHEN qual ILIKE '%admin_dashboard%' THEN 'Uses admin_dashboard table'
        WHEN qual ILIKE '%profiles%' AND qual ILIKE '%role%' AND qual ILIKE '%admin%' THEN 'Uses profiles.role = admin'
        ELSE 'Other logic'
    END as admin_check_method
FROM pg_policies
WHERE schemaname = 'storage' 
  AND tablename = 'objects'
  AND (policyname ILIKE '%admin%' OR policyname ILIKE '%deal%')
ORDER BY policyname;

-- ============================================================================
-- 5. CHECK REQUIRED COLUMNS ON trusted_partner_discounts
-- ============================================================================
SELECT 
    '5. TRUSTED_PARTNER_DISCOUNTS COLUMNS' as check_section,
    column_name,
    data_type,
    is_nullable,
    column_default,
    CASE 
        WHEN column_name IN ('id', 'trusted_partner_id', 'business_id', 'name', 
                             'description', 'item_name', 'item_price') 
        THEN '✅ Required for deal creation'
        WHEN column_name = 'image_url' 
        THEN '✅ Required for image upload'
        WHEN column_name IN ('deal_category', 'deal_type', 'is_active') 
        THEN '✓ Important optional field'
        ELSE '✓ Optional'
    END as importance
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'trusted_partner_discounts'
ORDER BY ordinal_position;

-- ============================================================================
-- 6. VERIFY FOREIGN KEY CONSTRAINTS
-- ============================================================================
SELECT 
    '6. DISCOUNT TABLE FOREIGN KEYS' as check_section,
    conname as constraint_name,
    pg_get_constraintdef(c.oid) as constraint_definition,
    CASE 
        WHEN conname LIKE '%trusted_partner%' 
        THEN '✅ trusted_partner_id constraint'
        WHEN conname LIKE '%business%' 
        THEN '✅ business_id constraint'
        ELSE '✓ Other FK'
    END as status
FROM pg_constraint c
JOIN pg_namespace n ON n.oid = c.connamespace
WHERE contype = 'f'
  AND n.nspname = 'public'
  AND conrelid = 'trusted_partner_discounts'::regclass;

-- ============================================================================
-- 7. CHECK ADMIN ROLE IDENTIFICATION METHOD
-- ============================================================================
SELECT 
    '7. ADMIN ROLE IDENTIFICATION METHOD' as check_section,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema = 'public' 
              AND table_name = 'admin_dashboard'
        ) 
        THEN '✅ Using admin_dashboard table for admin identification'
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = 'profiles' 
              AND column_name = 'role'
        ) 
        THEN '✅ Using profiles.role column for admin identification'
        ELSE '❌ No admin identification method found'
    END as result,
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables 
                     WHERE table_schema = 'public' AND table_name = 'admin_dashboard')
        THEN 'admin_dashboard'
        WHEN EXISTS (SELECT 1 FROM information_schema.columns 
                     WHERE table_schema = 'public' AND table_name = 'profiles' 
                     AND column_name = 'role')
        THEN 'profiles.role'
        ELSE 'none'
    END as method;

-- ============================================================================
-- 8. TEST ADMIN IDENTIFICATION - PROFILES.ROLE METHOD
-- ============================================================================
-- This simulates how the app checks if a user is an admin using profiles.role
SELECT 
    '8. ADMIN USERS CHECK (profiles.role)' as check_section,
    COUNT(*) as admin_count,
    CASE 
        WHEN COUNT(*) > 0 
        THEN '✅ Admin users exist in profiles table'
        ELSE '⚠️ No admin users found in profiles'
    END as status
FROM profiles
WHERE role = 'admin';

-- ============================================================================
-- 9. STORAGE BUCKET VERIFICATION
-- ============================================================================
SELECT 
    '9. STORAGE BUCKETS' as check_section,
    id,
    name,
    public,
    CASE 
        WHEN name = 'business-bills' 
        THEN '✅ business-bills bucket (used for deal images)'
        ELSE '✓ Other bucket'
    END as relevance
FROM storage.buckets
WHERE name IN ('business-bills', 'deal-images', 'partner-logos')
ORDER BY name;

-- ============================================================================
-- 10. SUMMARY - ADMIN DEAL CREATION READINESS
-- ============================================================================
SELECT 
    '10. SUMMARY - ADMIN DEAL CREATION CHECK' as check_section,
    (SELECT COUNT(*) FROM information_schema.columns 
     WHERE table_schema = 'public' AND table_name = 'businesses' 
       AND column_name = 'allow_admin_deal_creation') as has_permission_column,
    (SELECT COUNT(*) FROM pg_policies 
     WHERE schemaname = 'public' AND tablename = 'trusted_partner_discounts' 
       AND policyname ILIKE '%admin%' AND cmd = 'INSERT') as has_admin_insert_policy,
    (SELECT COUNT(*) FROM pg_policies 
     WHERE schemaname = 'storage' AND tablename = 'objects' 
       AND policyname ILIKE '%admin%' AND policyname ILIKE '%deal%' 
       AND cmd = 'INSERT') as has_admin_storage_policy,
    (SELECT COUNT(*) FROM storage.buckets 
     WHERE name = 'business-bills') as has_storage_bucket,
    (SELECT COUNT(*) FROM profiles WHERE role = 'admin') as admin_user_count,
    CASE 
        WHEN (SELECT COUNT(*) FROM information_schema.columns 
              WHERE table_schema = 'public' AND table_name = 'businesses' 
                AND column_name = 'allow_admin_deal_creation') > 0
             AND (SELECT COUNT(*) FROM storage.buckets 
                  WHERE name = 'business-bills') > 0
             AND (SELECT COUNT(*) FROM profiles WHERE role = 'admin') > 0
        THEN '✅ BASIC SETUP COMPLETE - Check individual policy results above'
        ELSE '❌ MISSING COMPONENTS - Review failures above'
    END as overall_status;

-- ============================================================================
-- 11. RECOMMENDED FIX (if needed)
-- ============================================================================
-- Uncomment and run these if the checks above show missing components:

/*
-- Add allow_admin_deal_creation column if missing:
ALTER TABLE businesses 
ADD COLUMN IF NOT EXISTS allow_admin_deal_creation BOOLEAN DEFAULT false;

-- Create admin INSERT policy for trusted_partner_discounts if missing:
-- NOTE: This uses profiles.role = 'admin' for admin detection
DROP POLICY IF EXISTS "Admins can create deals for authorized partners" 
ON trusted_partner_discounts;

CREATE POLICY "Admins can create deals for authorized partners" 
ON trusted_partner_discounts
FOR INSERT 
WITH CHECK (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = auth.uid() 
          AND role = 'admin'
    )
    AND EXISTS (
        SELECT 1 FROM businesses b
        WHERE b.owner_member_id = trusted_partner_id
          AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
);

-- Create admin storage policy for deal image uploads if missing:
DROP POLICY IF EXISTS "Admins can upload deal images for authorized partners" 
ON storage.objects;

CREATE POLICY "Admins can upload deal images for authorized partners" 
ON storage.objects
FOR INSERT 
TO authenticated
WITH CHECK (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
    AND EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = auth.uid() 
          AND role = 'admin'
    )
    AND EXISTS (
        SELECT 1 FROM businesses b
        WHERE b.owner_member_id = (storage.foldername(name))[2]::uuid
          AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
);
*/
