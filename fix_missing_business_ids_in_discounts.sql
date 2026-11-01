-- Fix missing business_id in trusted_partner_discounts table
-- This is CRITICAL for receipt generation

-- First, check how many discounts are missing business_id
SELECT 
    'Discounts missing business_id' as issue,
    COUNT(*) as count
FROM trusted_partner_discounts
WHERE business_id IS NULL;

-- Show which discounts are affected
SELECT 
    id,
    trusted_partner_id,
    name,
    business_id
FROM trusted_partner_discounts
WHERE business_id IS NULL;

-- Update all discounts to have business_id based on their trusted_partner_id
-- This matches the logic in the app: business.owner_member_id = discount.trusted_partner_id
UPDATE trusted_partner_discounts tpd
SET 
    business_id = (
        SELECT b.id 
        FROM businesses b 
        WHERE b.owner_member_id = tpd.trusted_partner_id
        LIMIT 1
    ),
    updated_at = NOW()
WHERE 
    tpd.business_id IS NULL
    AND EXISTS (
        SELECT 1 
        FROM businesses b 
        WHERE b.owner_member_id = tpd.trusted_partner_id
    );

-- Verify the fix
SELECT 
    'After fix - Discounts still missing business_id' as status,
    COUNT(*) as count
FROM trusted_partner_discounts
WHERE business_id IS NULL;

-- Show all discounts with their business info
SELECT 
    tpd.id,
    tpd.name,
    tpd.trusted_partner_id,
    tpd.business_id,
    b.name as business_name
FROM trusted_partner_discounts tpd
LEFT JOIN businesses b ON b.id = tpd.business_id
ORDER BY tpd.created_at DESC
LIMIT 10;

-- Check if any discounts still can't find a business
-- These trusted partners need to create a business profile
SELECT 
    tpd.id,
    tpd.trusted_partner_id,
    tpd.name,
    'No business found for this trusted partner' as issue
FROM trusted_partner_discounts tpd
WHERE tpd.business_id IS NULL;
