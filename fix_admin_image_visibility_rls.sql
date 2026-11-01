-- Fix: Allow admins to view deal images they upload
-- Problem: Admin-uploaded images not visible to admins or members
-- Root Cause: Admin SELECT policy requires allow_admin_deal_creation=true
--             But members can't view images because policy is too restrictive

-- Step 1: Remove the overly-restrictive admin SELECT policy that required allow_admin_deal_creation
DROP POLICY IF EXISTS "Admins can view deal images for authorized partners" ON storage.objects;

-- Step 2: Create a new, more permissive admin policy
-- Admins can view ANY deal image (regardless of allow_admin_deal_creation)
-- This allows them to see images they upload
CREATE POLICY "Admins can view deal images" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
        EXISTS (
            SELECT 1
            FROM public.memberships m
            WHERE m.user_id = auth.uid()
              AND m.role = 'admin'
        )
    );

-- Step 3: Ensure members can view all deal images (unconditional)
-- This is already correct but let's verify it exists
DROP POLICY IF EXISTS "Members can view deal images" ON storage.objects;
CREATE POLICY "Members can view deal images" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%'
    );

-- Step 4: Ensure trusted partners can view their own images
-- This is already correct but let's verify
DROP POLICY IF EXISTS "Trusted partners can view deal images" ON storage.objects;
CREATE POLICY "Trusted partners can view deal images" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
        split_part(name, '/', 2) = auth.uid()::text
    );

-- Verify the policies
SELECT 
    policyname,
    permissive,
    cmd,
    CASE 
        WHEN cmd = 'SELECT' AND policyname LIKE '%view%' THEN '✓ View policy'
        WHEN cmd = 'INSERT' THEN '✓ Upload policy'
        WHEN cmd = 'UPDATE' THEN '✓ Update policy'
        WHEN cmd = 'DELETE' THEN '✓ Delete policy'
        ELSE 'Other'
    END as policy_type
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND policyname LIKE '%deal image%'
ORDER BY cmd, policyname;
