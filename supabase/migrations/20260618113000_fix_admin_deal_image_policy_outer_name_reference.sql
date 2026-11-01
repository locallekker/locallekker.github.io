-- Migration: Fix admin deal image policy to reference storage.objects.name explicitly.
--
-- Why:
-- - In correlated subqueries, unqualified `name` can resolve to businesses.name,
--   producing incorrect folder checks.
-- - Remove overlapping UPDATE admin policies and keep one canonical FOR ALL policy.

BEGIN;

-- Remove overlapping admin policies before recreating canonical policy.
DROP POLICY IF EXISTS "Admins can manage partner deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can update deal images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can update deal images for authorized partners" ON storage.objects;

-- Canonical admin policy using explicit outer reference `objects.name`.
CREATE POLICY "Admins can manage partner deal images" ON storage.objects
  FOR ALL USING (
    bucket_id = 'business-bills'
    AND (storage.foldername(objects.name))[1] = 'deal_images'
    AND EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
    )
    AND EXISTS (
      SELECT 1
      FROM public.businesses b
      WHERE b.owner_member_id::text = (storage.foldername(objects.name))[2]
        AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
  ) WITH CHECK (
    bucket_id = 'business-bills'
    AND (storage.foldername(objects.name))[1] = 'deal_images'
    AND EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = auth.uid()
        AND m.role = 'admin'
    )
    AND EXISTS (
      SELECT 1
      FROM public.businesses b
      WHERE b.owner_member_id::text = (storage.foldername(objects.name))[2]
        AND COALESCE(b.allow_admin_deal_creation, false) = true
    )
  );

COMMIT;
