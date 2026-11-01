-- Fix script for business_id foreign key constraint violation
-- This updates trusted_partner_discounts to use the correct business_id

-- STEP 1: Update discounts that have wrong business_id
-- This finds the correct business_id from the businesses table using trusted_partner_id
UPDATE trusted_partner_discounts tpd
SET business_id = b.id
FROM businesses b
WHERE b.owner_member_id = tpd.trusted_partner_id
  AND tpd.business_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM businesses WHERE id = tpd.business_id
  );

-- STEP 2: Update discounts that have NULL business_id
UPDATE trusted_partner_discounts tpd
SET business_id = b.id
FROM businesses b
WHERE b.owner_member_id = tpd.trusted_partner_id
  AND tpd.business_id IS NULL;

-- STEP 3: Verify the fix
SELECT 
    tpd.id as discount_id,
    tpd.name as deal_name,
    tpd.business_id,
    b.name as business_name,
    CASE 
        WHEN b.id IS NULL THEN '❌ STILL MISSING'
        ELSE '✅ FIXED'
    END as status
FROM trusted_partner_discounts tpd
LEFT JOIN businesses b ON b.id = tpd.business_id
ORDER BY tpd.created_at DESC
LIMIT 20;

-- STEP 4: Check for any trusted partners without businesses (these will still have issues)
SELECT 
    p.id as trusted_partner_id,
    p.email,
    p.name,
    COUNT(tpd.id) as discount_count
FROM profiles p
LEFT JOIN trusted_partner_discounts tpd ON tpd.trusted_partner_id = p.id
LEFT JOIN businesses b ON b.owner_member_id = p.id
WHERE p.role = 'trusted_partner'
  AND b.id IS NULL
  AND tpd.id IS NOT NULL
GROUP BY p.id, p.email, p.name;

-- NOTE: For trusted partners without businesses, you'll need to either:
-- 1. Create a business for them first
-- 2. Delete their discounts (if they're invalid)
