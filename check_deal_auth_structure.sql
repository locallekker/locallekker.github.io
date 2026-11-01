-- Check deal_authorizations table structure
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'deal_authorizations'
ORDER BY ordinal_position;

-- Check if business_id column allows NULL
SELECT 
  table_name,
  column_name,
  is_nullable,
  data_type
FROM information_schema.columns
WHERE table_name = 'deal_authorizations' 
  AND column_name = 'business_id';
