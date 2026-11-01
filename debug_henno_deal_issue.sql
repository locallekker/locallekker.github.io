-- Compare Henno and Clyde profiles in detail to find differences
SELECT 
  email,
  name,
  verified,
  subscription,
  member_terms_accepted,
  role,
  email_verified,
  created_at,
  -- Check if there are any other relevant fields
  id
FROM profiles
WHERE email IN ('bekkerhenno518@gmail.com', 'clydemflan@gmail.com')
ORDER BY email;

-- Check if there are existing deal authorizations for both users
SELECT 
  user_id,
  deal_id,
  status,
  created_at
FROM deal_authorizations
WHERE user_id IN (
  '4c61beb9-0324-43c8-a42c-e1c675032b30',  -- Henno
  '6c815ef9-5e8a-498b-927c-9d807421f791'   -- Clyde
)
ORDER BY created_at DESC;
