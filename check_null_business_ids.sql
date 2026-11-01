-- Check for discounts with NULL business_id
SELECT 
  id,
  name,
  business_id,
  trusted_partner_id,
  is_active,
  created_at
FROM trusted_partner_discounts
WHERE business_id IS NULL
ORDER BY created_at DESC;

-- Show all active discounts with business details
SELECT 
  d.id as discount_id,
  d.name as deal_name,
  d.business_id,
  b.name as business_name,
  d.trusted_partner_id,
  p.email as tp_email,
  d.is_active
FROM trusted_partner_discounts d
LEFT JOIN businesses b ON d.business_id = b.id
LEFT JOIN profiles p ON d.trusted_partner_id = p.id
WHERE d.is_active = true
ORDER BY d.created_at DESC;
