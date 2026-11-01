-- Check RLS policies on deal_authorizations table
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
WHERE tablename = 'deal_authorizations'
ORDER BY cmd, policyname;
