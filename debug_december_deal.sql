-- Check the December soecial discount details
SELECT 
  d.id as discount_id,
  d.name,
  d.business_id,
  d.trusted_partner_id,
  b.id as business_exists,
  b.name as business_name,
  p.id as tp_user_exists,
  p.email as tp_email
FROM trusted_partner_discounts d
LEFT JOIN businesses b ON d.business_id = b.id
LEFT JOIN profiles p ON d.trusted_partner_id = p.id
WHERE d.name = 'December soecial'
LIMIT 1;

-- Check the foreign key constraint details
SELECT
    tc.constraint_name, 
    tc.table_name, 
    kcu.column_name, 
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name 
FROM information_schema.table_constraints AS tc 
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY' 
  AND tc.table_name='deal_authorizations'
  AND tc.constraint_name = 'deal_authorizations_business_id_fkey';
