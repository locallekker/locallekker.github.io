-- Fix user IDs in trusted_partner_id - replace with correct business_id
-- This fixes all 8 records that have the same bug the code fix prevents

-- Show affected records BEFORE the fix
SELECT 
    id,
    business_id,
    trusted_partner_id,
    discount_id,
    status,
    created_at
FROM deal_authorizations
WHERE trusted_partner_id IN (
    SELECT id FROM profiles
)
ORDER BY created_at DESC;

-- Apply the fix: Copy business_id to trusted_partner_id for all records with user IDs
UPDATE deal_authorizations
SET trusted_partner_id = business_id
WHERE trusted_partner_id IN (
    SELECT id FROM profiles
);

-- Show results AFTER the fix
SELECT 
    COUNT(*) as records_fixed,
    COUNT(DISTINCT business_id) as affected_businesses
FROM deal_authorizations
WHERE trusted_partner_id = business_id;

-- Final verification: All records should now have matching IDs
SELECT 
    id,
    business_id,
    trusted_partner_id,
    CASE 
        WHEN trusted_partner_id = business_id THEN '✅ Fixed'
        WHEN trusted_partner_id IS NULL THEN '⚠️ NULL trusted_partner_id'
        ELSE '❌ Still mismatched'
    END as status
FROM deal_authorizations
ORDER BY created_at DESC
LIMIT 20;

-- Summary
SELECT 
    COUNT(*) FILTER (WHERE trusted_partner_id IS NULL) as null_tp_id,
    COUNT(*) FILTER (WHERE trusted_partner_id = business_id) as matching_ids,
    COUNT(*) FILTER (WHERE trusted_partner_id != business_id) as mismatched_ids,
    COUNT(*) as total_authorizations
FROM deal_authorizations;
