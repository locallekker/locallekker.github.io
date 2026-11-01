-- Comprehensive fix for deal image upload RLS policies
-- This ensures trusted partners can upload deal images to their own folders
-- and members can view all deal images

BEGIN;

-- First, drop any existing conflicting policies to avoid duplicates
DROP POLICY IF EXISTS "Trusted partners can upload deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can view deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can update deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can delete deal images" ON storage.objects;
DROP POLICY IF EXISTS "Members can view deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can manage deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can upload own deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can update own deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can delete own deal images" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view deal images" ON storage.objects;

-- Create policy for trusted partners to upload deal images to their own folder
-- Path structure: deal_images/{user_id}/{filename}
CREATE POLICY "Trusted partners can upload own deal images" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Allow trusted partners to update their own deal images
CREATE POLICY "Trusted partners can update own deal images" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Allow trusted partners to delete their own deal images
CREATE POLICY "Trusted partners can delete own deal images" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Allow everyone to view deal images (public URLs)
CREATE POLICY "Anyone can view deal images" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
  );

-- Allow admins to manage deal images for partners who allow admin deal creation
-- Path structure: deal_images/{partner_id}/{filename}
CREATE POLICY "Admins can manage partner deal images" ON storage.objects
  FOR ALL USING (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
    AND EXISTS (
      SELECT 1 
      FROM public.businesses b
      JOIN public.memberships m ON m.user_id = auth.uid() AND m.role = 'admin'
      WHERE b.owner_member_id::text = (storage.foldername(name))[2]
        AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
  ) WITH CHECK (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
    AND EXISTS (
      SELECT 1 
      FROM public.businesses b
      JOIN public.memberships m ON m.user_id = auth.uid() AND m.role = 'admin'
      WHERE b.owner_member_id::text = (storage.foldername(name))[2]
        AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
  );

COMMIT;
