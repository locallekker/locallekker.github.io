-- Diagnostic script to check why members can't see deals
-- Check if trusted_partner_discounts has the business_id column and proper data

-- 1. Check table structure
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'trusted_partner_discounts'
ORDER BY ordinal_position;

-- 2. Check current RLS policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies WHERE tablename = 'trusted_partner_discounts'
ORDER BY policyname;

-- 3. Check discount data and business relationships
SELECT
    tpd.id,
    tpd.name,
    tpd.business_id,
    tpd.trusted_partner_id,
    b.name as business_name,
    b.owner_member_id
FROM trusted_partner_discounts tpd
LEFT JOIN businesses b ON tpd.business_id = b.id;

-- 4. Check how many discounts have valid business_id
SELECT
    COUNT(*) as total_discounts,
    COUNT(CASE WHEN business_id IS NOT NULL THEN 1 END) as with_business_id,
    COUNT(CASE WHEN business_id IS NULL THEN 1 END) as without_business_id
FROM trusted_partner_discounts;

-- 5. Test what a member can see (simulate auth.uid())
-- This should return all discounts if the policy works
SELECT COUNT(*) as member_visible_discounts FROM trusted_partner_discounts;