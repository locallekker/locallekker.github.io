-- Fix storage RLS policy for TPs uploading deal images
-- The current policy only allows upload if folder name matches business owner_member_id
-- We need to allow TPs to upload to their own deal_images/{user_id}/ folder

BEGIN;

-- Create policy to allow trusted partners to upload deal images to their own folder
CREATE POLICY "Trusted partners can upload own deal images" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Also allow them to update/delete their own deal images
CREATE POLICY "Trusted partners can update own deal images" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

CREATE POLICY "Trusted partners can delete own deal images" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Allow everyone to view deal images (they're public URLs anyway)
CREATE POLICY "Anyone can view deal images" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
  );

COMMIT;
