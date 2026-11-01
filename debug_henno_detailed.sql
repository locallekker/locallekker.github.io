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

-- Check if Henno has any existing deal authorizations
SELECT 
  id,
  member_id,
  discount_id,
  status,
  payment_method,
  amount,
  created_at
FROM deal_authorizations
WHERE member_id = '4c61beb9-0324-43c8-a42c-e1c675032b30'  -- Henno's ID
ORDER BY created_at DESC;

-- Check Henno's full profile for any missing fields
SELECT 
  id,
  email,
  name,
  surname,
  role,
  verified,
  subscription,
  member_terms_accepted,
  email_verified,
  created_at
FROM profiles
WHERE id = '4c61beb9-0324-43c8-a42c-e1c675032b30';  -- Henno's ID
