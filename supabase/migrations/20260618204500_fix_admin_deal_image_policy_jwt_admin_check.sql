-- Fix admin deal image policy checks to avoid auth.users joins in storage RLS
-- Some environments reject cross-schema user table checks in storage policy expressions.

BEGIN;

DROP POLICY IF EXISTS "Admins can upload deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can update deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can view deal images" ON storage.objects;

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
    OR lower(coalesce(auth.jwt() ->> 'email', '')) = 'locallekkerclub@gmail.com'
    OR lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'admin'
    OR lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'user_type', '')) = 'admin'
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
    OR lower(coalesce(auth.jwt() ->> 'email', '')) = 'locallekkerclub@gmail.com'
    OR lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'admin'
    OR lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'user_type', '')) = 'admin'
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
    OR lower(coalesce(auth.jwt() ->> 'email', '')) = 'locallekkerclub@gmail.com'
    OR lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'admin'
    OR lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'user_type', '')) = 'admin'
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
    OR lower(coalesce(auth.jwt() ->> 'email', '')) = 'locallekkerclub@gmail.com'
    OR lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'admin'
    OR lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'user_type', '')) = 'admin'
  )
);

COMMIT;
