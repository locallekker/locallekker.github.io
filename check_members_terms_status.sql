-- Check members' terms acceptance and verification status
SELECT 
  'Member' as user_type,
  id,
  email,
  name,
  surname,
  role,
  member_terms_accepted,
  member_terms_accepted_at,
  subscription,
  verified,
  created_at
FROM profiles
WHERE role = 'member'
ORDER BY created_at DESC;
