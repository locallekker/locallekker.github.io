-- Fix missing WITH CHECK clauses for deal image upload policies

BEGIN;

-- Drop the broken INSERT policies
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

-- Verify the fixed policies
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
