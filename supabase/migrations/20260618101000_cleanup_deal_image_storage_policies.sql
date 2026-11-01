-- Migration: Cleanup and normalize deal image storage RLS policies.
--
-- Why:
-- - Production has overlapping/legacy policies for deal image paths.
-- - Some policy expressions use incorrect path sources (e.g., b.name), which is risky.
-- - We standardize on business-bills/deal_images/{owner_id}/{file} and keep one policy set.

BEGIN;

-- Remove legacy and duplicate policies related to deal images.
DROP POLICY IF EXISTS "Admins can manage deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can manage partner deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete deal images for authorized partners" ON storage.objects;
DROP POLICY IF EXISTS "Admins can upload deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can upload deal images for authorized partners" ON storage.objects;
DROP POLICY IF EXISTS "Admins can view all deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can view deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can upload own deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can update own deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can delete own deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can view own deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can upload deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can update deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can delete deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can view deal images" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view deal images" ON storage.objects;
DROP POLICY IF EXISTS "Members can view deal images" ON storage.objects;
DROP POLICY IF EXISTS "Allow public read of deal-images" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated uploads to deal-images" ON storage.objects;
DROP POLICY IF EXISTS "Allow owners to manage deal-images" ON storage.objects;

-- Canonical member/public read policy for deal images.
CREATE POLICY "Anyone can view deal images" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
  );

-- Trusted partners manage only their own deal image folder.
CREATE POLICY "Trusted partners can upload own deal images" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

CREATE POLICY "Trusted partners can update own deal images" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
    AND (storage.foldername(name))[2] = auth.uid()::text
  ) WITH CHECK (
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

-- Admins can manage partner deal images only when partner has opted in.
CREATE POLICY "Admins can manage partner deal images" ON storage.objects
  FOR ALL USING (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
    AND EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
    )
    AND EXISTS (
      SELECT 1
      FROM public.businesses b
      WHERE b.owner_member_id::text = (storage.foldername(name))[2]
        AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
  ) WITH CHECK (
    bucket_id = 'business-bills'
    AND (storage.foldername(name))[1] = 'deal_images'
    AND EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
    )
    AND EXISTS (
      SELECT 1
      FROM public.businesses b
      WHERE b.owner_member_id::text = (storage.foldername(name))[2]
        AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
  );

COMMIT;
