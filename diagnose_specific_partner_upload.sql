-- Diagnostic query for specific partner upload issue
-- Partner ID: 78e67dc8-583b-4fe0-84e6-aa4d0c55a92e
-- Admin ID: 985fa2aa-45c7-450a-a8b8-ff63934a6193

-- 1. Check if admin user is actually an admin
SELECT 
    '1. Admin Check' as step,
    m.user_id,
    m.role,
    CASE WHEN m.role = 'admin' THEN '✓ IS ADMIN' ELSE '✗ NOT ADMIN' END as status
FROM public.memberships m
WHERE m.user_id = '985fa2aa-45c7-450a-a8b8-ff63934a6193';

-- 2. Check if partner exists and has allow_admin_deal_creation enabled
SELECT 
    '2. Partner Permission Check' as step,
    b.id,
    b.name,
    b.owner_member_id,
    b.allow_admin_deal_creation,
    CASE 
        WHEN b.allow_admin_deal_creation = true THEN '✓ ADMIN CAN CREATE DEALS'
        WHEN b.allow_admin_deal_creation = false THEN '✗ ADMIN CANNOT CREATE DEALS (FALSE)'
        WHEN b.allow_admin_deal_creation IS NULL THEN '✗ ADMIN CANNOT CREATE DEALS (NULL)'
    END as status
FROM public.businesses b
WHERE b.owner_member_id = '78e67dc8-583b-4fe0-84e6-aa4d0c55a92e';

-- 3. Test the exact policy condition for INSERT
SELECT 
    '3. Policy Simulation for INSERT' as step,
    EXISTS (
        SELECT 1 
        FROM public.memberships m 
        WHERE m.user_id = '985fa2aa-45c7-450a-a8b8-ff63934a6193'
          AND m.role = 'admin'
    ) as admin_check_passes,
    EXISTS (
        SELECT 1 
        FROM public.businesses b
        WHERE b.owner_member_id::text = split_part('deal_images/78e67dc8-583b-4fe0-84e6-aa4d0c55a92e/test.jpg', '/', 2)
          AND COALESCE(b.allow_admin_deal_creation, false) = true
    ) as business_check_passes,
    split_part('deal_images/78e67dc8-583b-4fe0-84e6-aa4d0c55a92e/test.jpg', '/', 2) as extracted_partner_id,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM public.memberships m 
            WHERE m.user_id = '985fa2aa-45c7-450a-a8b8-ff63934a6193'
              AND m.role = 'admin'
        ) AND EXISTS (
            SELECT 1 
            FROM public.businesses b
            WHERE b.owner_member_id::text = split_part('deal_images/78e67dc8-583b-4fe0-84e6-aa4d0c55a92e/test.jpg', '/', 2)
              AND COALESCE(b.allow_admin_deal_creation, false) = true
        ) THEN '✓ POLICY SHOULD PASS'
        ELSE '✗ POLICY WILL FAIL'
    END as overall_result;

-- 4. Check all storage policies
SELECT 
    '4. Storage Policies' as step,
    policyname,
    cmd as operation,
    qual as using_clause,
    with_check as with_check_clause
FROM pg_policies
WHERE schemaname = 'storage' 
  AND tablename = 'objects'
  AND policyname LIKE '%deal image%'
ORDER BY policyname;
