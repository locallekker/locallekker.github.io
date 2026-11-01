-- Check members' terms acceptance status
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

-- Check trusted partners' terms acceptance status
SELECT 
  'Trusted Partner' as user_type,
  id,
  email,
  name,
  surname,
  role,
  partner_terms_accepted,
  partner_terms_accepted_at,
  subscription,
  verified,
  is_tp_member,
  created_at
FROM profiles
WHERE role = 'trusted_partner'
ORDER BY created_at DESC;
