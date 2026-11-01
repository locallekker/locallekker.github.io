-- Check That Old Oak's current status
SELECT 
  id,
  email,
  name,
  surname,
  role,
  verified,
  partner_terms_accepted,
  partner_terms_accepted_at,
  partner_terms_version,
  is_tp_member,
  member_terms_accepted,
  subscription,
  created_at,
  updated_at
FROM profiles
WHERE email ILIKE '%craft%' OR name ILIKE '%oak%'
ORDER BY created_at DESC
LIMIT 5;
