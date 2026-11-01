-- Test: Select trusted_partner_id and business_id from a specific discount
SELECT 
  id,
  name,
  trusted_partner_id,
  business_id
FROM trusted_partner_discounts
WHERE name = 'December soecial'
LIMIT 1;

-- Test: Verify this works even if we use only those columns
SELECT 
  trusted_partner_id,
  business_id
FROM trusted_partner_discounts
WHERE id = '4fc0d743-51e8-4a7b-8122-65427d45bbea'
LIMIT 1;
