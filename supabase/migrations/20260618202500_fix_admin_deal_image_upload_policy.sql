-- Fix admin deal image upload permissions for business-bills/deal_images/*
-- Goal: admins can always upload/manage deal images; trusted partners keep own-folder access.

BEGIN;

-- Drop existing conflicting deal image policies
DROP POLICY IF EXISTS "Trusted partners can upload own deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can update own deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can delete own deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can upload deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can update deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can delete deal images" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can view deal images" ON storage.objects;
DROP POLICY IF EXISTS "Members can view deal images" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can manage deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can manage partner deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can upload deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can view all deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can update deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can upload deal images for authorized partners" ON storage.objects;
DROP POLICY IF EXISTS "Admins can view deal images for authorized partners" ON storage.objects;
DROP POLICY IF EXISTS "Admins can update deal images for authorized partners" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete deal images for authorized partners" ON storage.objects;
DROP POLICY IF EXISTS "Admins can view deal images" ON storage.objects;

-- Trusted partners: manage only their own folder deal_images/{auth.uid()}/...
CREATE POLICY "Trusted partners can upload own deal images" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'business-bills'
  AND name LIKE 'deal_images/%'
  AND split_part(name, '/', 2) = auth.uid()::text
);

CREATE POLICY "Trusted partners can update own deal images" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'business-bills'
  AND name LIKE 'deal_images/%'
  AND split_part(name, '/', 2) = auth.uid()::text
);

CREATE POLICY "Trusted partners can delete own deal images" ON storage.objects
FOR DELETE USING (
  bucket_id = 'business-bills'
  AND name LIKE 'deal_images/%'
  AND split_part(name, '/', 2) = auth.uid()::text
);

-- All authenticated users can view deal images
CREATE POLICY "Members can view deal images" ON storage.objects
FOR SELECT USING (
  bucket_id = 'business-bills'
  AND name LIKE 'deal_images/%'
);

-- Admin detection helper inlined for policy checks
-- Supports all known admin models in this codebase:
-- 1) memberships.role = 'admin'
-- 2) known admin email fallback used in app (locallekkerclub@gmail.com)

CREATE POLICY "Admins can upload deal images" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'business-bills'
  AND name LIKE 'deal_images/%'
  AND (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
    )
    OR EXISTS (
      SELECT 1
      FROM auth.users u
      WHERE u.id = auth.uid()
        AND u.email = 'locallekkerclub@gmail.com'
    )
  )
);

CREATE POLICY "Admins can update deal images" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'business-bills'
  AND name LIKE 'deal_images/%'
  AND (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
    )
    OR EXISTS (
      SELECT 1
      FROM auth.users u
      WHERE u.id = auth.uid()
        AND u.email = 'locallekkerclub@gmail.com'
    )
  )
);

CREATE POLICY "Admins can delete deal images" ON storage.objects
FOR DELETE USING (
  bucket_id = 'business-bills'
  AND name LIKE 'deal_images/%'
  AND (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
    )
    OR EXISTS (
      SELECT 1
      FROM auth.users u
      WHERE u.id = auth.uid()
        AND u.email = 'locallekkerclub@gmail.com'
    )
  )
);

CREATE POLICY "Admins can view deal images" ON storage.objects
FOR SELECT USING (
  bucket_id = 'business-bills'
  AND name LIKE 'deal_images/%'
  AND (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
    )
    OR EXISTS (
      SELECT 1
      FROM auth.users u
      WHERE u.id = auth.uid()
        AND u.email = 'locallekkerclub@gmail.com'
    )
  )
);

COMMIT;
