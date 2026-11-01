-- Diagnostic SQL to check deal image storage RLS configuration
-- Run this to verify if the fix has been applied

-- 1. Check if business-bills bucket exists
SELECT 'BUCKET CHECK:' as check_type, 
       name, 
       public,
       CASE WHEN id = 'business-bills' THEN '✅ EXISTS' ELSE '❌ MISSING' END as status
FROM storage.buckets 
WHERE id = 'business-bills';

-- 2. Check existing storage policies for deal_images
SELECT 'STORAGE POLICIES:' as check_type,
       policyname as policy_name,
       cmd as operation,
       CASE 
         WHEN policyname LIKE '%deal image%' OR policyname LIKE '%deal_image%' THEN '✅ RELEVANT'
         ELSE 'ℹ️  OTHER'
       END as relevance
FROM pg_policies 
WHERE schemaname = 'storage' 
  AND tablename = 'objects'
  AND (policyname LIKE '%deal%' OR policyname LIKE '%image%')
ORDER BY policyname;

-- 3. Check specifically for the new policies we're adding
SELECT 'NEW POLICIES STATUS:' as check_type,
       CASE 
         WHEN EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Trusted partners can upload own deal images') 
         THEN '✅ UPLOAD POLICY EXISTS'
         ELSE '❌ UPLOAD POLICY MISSING - MIGRATION NEEDED'
       END as upload_policy,
       CASE 
         WHEN EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Anyone can view deal images') 
         THEN '✅ VIEW POLICY EXISTS'
         ELSE '❌ VIEW POLICY MISSING - MIGRATION NEEDED'
       END as view_policy;

-- 4. List ALL current storage policies for business-bills bucket
SELECT 'ALL BUSINESS-BILLS POLICIES:' as check_type,
       policyname,
       cmd as operation,
       qual as using_clause,
       with_check as with_check_clause
FROM pg_policies 
WHERE schemaname = 'storage' 
  AND tablename = 'objects'
ORDER BY policyname;

-- 5. Check if there are any conflicting old policies that need to be dropped
SELECT 'CONFLICTING POLICIES:' as check_type,
       policyname,
       CASE 
         WHEN policyname IN (
           'Trusted partners can upload deal images',
           'Trusted partners can view deal images', 
           'Trusted partners can update deal images',
           'Trusted partners can delete deal images',
           'Members can view deal images',
           'Admins can manage deal images'
         ) THEN '⚠️  OLD POLICY - WILL BE REPLACED'
         ELSE '✅ OK'
       END as status
FROM pg_policies 
WHERE schemaname = 'storage' 
  AND tablename = 'objects'
  AND policyname LIKE '%deal%';

-- 6. Summary recommendation
SELECT 'RECOMMENDATION:' as check_type,
       CASE 
         WHEN NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Trusted partners can upload own deal images') 
         THEN '🔧 RUN MIGRATION: supabase/migrations/20260207182830_fix_deal_image_upload_rls.sql'
         WHEN EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Trusted partners can upload own deal images') 
         THEN '✅ MIGRATION ALREADY APPLIED - DATABASE IS ALIGNED'
         ELSE '⚠️  PARTIAL CONFIGURATION - REVIEW POLICIES'
       END as action_needed;
