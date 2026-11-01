-- Fix NULL trusted_partner_id values in deal_authorizations
-- This copies business_id to trusted_partner_id for the 11 affected records

-- Show affected records BEFORE the fix
SELECT 
    id,
    member_id,
    business_id,
    trusted_partner_id,
    discount_id,
    status,
    created_at
FROM deal_authorizations
WHERE trusted_partner_id IS NULL
ORDER BY created_at DESC;

-- Apply the fix: Copy business_id to trusted_partner_id
UPDATE deal_authorizations
SET trusted_partner_id = business_id
WHERE trusted_partner_id IS NULL
  AND business_id IS NOT NULL;

-- Show results AFTER the fix
SELECT 
    COUNT(*) FILTER (WHERE trusted_partner_id IS NULL) as remaining_null_tp_id,
    COUNT(*) FILTER (WHERE business_id IS NULL) as null_business_id,
    COUNT(*) FILTER (WHERE trusted_partner_id = business_id) as matching_ids,
    COUNT(*) as total
FROM deal_authorizations;

-- Verify all records now have valid trusted_partner_id
SELECT 
    id,
    business_id,
    trusted_partner_id,
    CASE 
        WHEN trusted_partner_id IS NULL THEN '❌ Still NULL'
        WHEN trusted_partner_id = business_id THEN '✅ Fixed - matches business_id'
        ELSE '⚠️ Different from business_id'
    END as status
FROM deal_authorizations
ORDER BY created_at DESC
LIMIT 15;
