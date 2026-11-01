-- Find discounts with invalid business_id (doesn't exist in businesses table)
SELECT 
  d.id as discount_id,
  d.name as deal_name,
  d.business_id,
  d.trusted_partner_id,
  b.id as business_exists
FROM trusted_partner_discounts d
LEFT JOIN businesses b ON d.business_id = b.id
WHERE b.id IS NULL  -- business_id doesn't exist in businesses table
ORDER BY d.created_at DESC;

-- Check the specific businesses from the screenshots
SELECT 
  d.id,
  d.name,
  d.business_id,
  b.name as business_name,
  b.id as business_exists
FROM trusted_partner_discounts d
LEFT JOIN businesses b ON d.business_id = b.id
WHERE d.name IN (
  '10% off bill',
  '5% Off on Grass-fed steak',
  'Weekend Special',
  'December soecial',
  'Momberg special'
)
ORDER BY d.name;

-- Show all businesses to see what exists
SELECT id, name, owner_member_id, created_at
FROM businesses
ORDER BY created_at DESC;
