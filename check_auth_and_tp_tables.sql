-- Check auth.users and trusted_partner_discounts for remaining traces
-- UID: 1916d77f-596f-4e9f-825f-dedf7a11bbf8

-- ============================================================================
-- 1. Check auth.users (Supabase Auth table)
-- ============================================================================
SELECT 
    'auth.users' as table_name,
    id,
    email,
    created_at,
    updated_at
FROM auth.users
WHERE id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- ============================================================================
-- 2. Check trusted_partner_discounts for any references
-- ============================================================================
SELECT 
    'trusted_partner_discounts' as table_name,
    COUNT(*) as total_rows,
    COUNT(DISTINCT business_id) as unique_businesses
FROM trusted_partner_discounts;

-- Show all trusted_partner_discounts if count is low
SELECT 
    tpd.id,
    tpd.business_id,
    b.name as business_name,
    b.owner_member_id,
    tpd.created_at
FROM trusted_partner_discounts tpd
LEFT JOIN businesses b ON b.id = tpd.business_id
ORDER BY tpd.created_at DESC;

-- ============================================================================
-- 3. Check if there are any orphaned rows in trusted_partner_discounts
--    (pointing to non-existent businesses)
-- ============================================================================
SELECT 
    tpd.id,
    tpd.business_id,
    'ORPHANED - Business does not exist' as status
FROM trusted_partner_discounts tpd
WHERE NOT EXISTS (
    SELECT 1 FROM businesses b WHERE b.id = tpd.business_id
);

-- ============================================================================
-- 4. Summary: Full cleanup status
-- ============================================================================
SELECT 'CLEANUP SUMMARY' as section;

SELECT 
    'profiles (should be 0)' as check_item,
    COUNT(*) as count
FROM profiles
WHERE id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
UNION ALL
SELECT 
    'memberships (should be 0)' as check_item,
    COUNT(*) as count
FROM memberships
WHERE user_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
UNION ALL
SELECT 
    'businesses (should be 0)' as check_item,
    COUNT(*) as count
FROM businesses
WHERE owner_member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
UNION ALL
SELECT 
    'auth.users (manual deletion required)' as check_item,
    COUNT(*) as count
FROM auth.users
WHERE id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
ORDER BY check_item;
