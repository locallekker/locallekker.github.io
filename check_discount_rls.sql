-- Check RLS policies on trusted_partner_discounts
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'trusted_partner_discounts'
ORDER BY cmd, policyname;
