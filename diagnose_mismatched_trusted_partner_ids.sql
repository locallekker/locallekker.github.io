-- Diagnose the mismatched trusted_partner_id values
-- Check if 78e67dc8-583b-4fe0-84e6-aa4d0c55a92e is a user ID or business ID

-- 1. Check if it's in the profiles table (user ID)
SELECT 
    'profiles' as table_name,
    id,
    email
FROM profiles
WHERE id = '78e67dc8-583b-4fe0-84e6-aa4d0c55a92e';

-- 2. Check if it's in the businesses table (business ID)
SELECT 
    'businesses' as table_name,
    id,
    name,
    owner_member_id
FROM businesses
WHERE id = '78e67dc8-583b-4fe0-84e6-aa4d0c55a92e';

-- 3. Check the other business ID
SELECT 
    'businesses' as table_name,
    id,
    name,
    owner_member_id
FROM businesses
WHERE id = '8692b21b-42c4-43fd-af23-fb0f37bc4068';

-- 4. Show the 8 problematic records with discount details
SELECT 
    da.id as deal_auth_id,
    da.business_id,
    da.trusted_partner_id,
    da.discount_id,
    da.status,
    da.created_at,
    tpd.name as deal_name,
    tpd.business_id as deal_business_id,
    b1.name as business_id_name,
    b2.name as trusted_partner_id_name
FROM deal_authorizations da
LEFT JOIN trusted_partner_discounts tpd ON da.discount_id = tpd.id
LEFT JOIN businesses b1 ON da.business_id = b1.id
LEFT JOIN businesses b2 ON da.trusted_partner_id = b2.id
WHERE da.trusted_partner_id != da.business_id
ORDER BY da.created_at DESC;

-- 5. Decision: Which ID should we keep?
-- If trusted_partner_id is a user ID (appears in profiles), we MUST fix it
-- If both are business IDs, we need to check which matches the discount's business_id
SELECT 
    da.id,
    da.business_id,
    da.trusted_partner_id,
    tpd.business_id as discount_business_id,
    CASE 
        WHEN p.id IS NOT NULL THEN '❌ URGENT FIX: trusted_partner_id is a USER ID'
        WHEN da.business_id = tpd.business_id THEN '✅ business_id matches discount - use this'
        WHEN da.trusted_partner_id = tpd.business_id THEN '⚠️ trusted_partner_id matches discount'
        ELSE '❓ Neither matches discount business_id'
    END as recommendation
FROM deal_authorizations da
LEFT JOIN trusted_partner_discounts tpd ON da.discount_id = tpd.id
LEFT JOIN profiles p ON da.trusted_partner_id = p.id
WHERE da.trusted_partner_id != da.business_id;
