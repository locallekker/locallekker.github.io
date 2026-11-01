-- =====================================================
-- FIND TP MEMBER
-- Search for the TP member across all roles and statuses
-- =====================================================

-- Check all profiles with is_tp_member flag (any role)
SELECT 
  'Profiles with is_tp_member = true (any role)' as search,
  id,
  name,
  surname,
  email,
  role,
  is_tp_member,
  verified,
  created_at
FROM profiles
WHERE is_tp_member = true;

-- Check memberships table for gateway = 'trusted_partner_key'
SELECT 
  'Memberships with trusted_partner_key gateway' as search,
  m.user_id,
  m.role,
  m.gateway,
  p.name,
  p.surname,
  p.email,
  p.is_tp_member,
  m.created_at
FROM memberships m
LEFT JOIN profiles p ON m.user_id = p.id
WHERE m.gateway = 'trusted_partner_key';

-- Check all members with any TP-related indicators
SELECT 
  'All member profiles' as search,
  id,
  name,
  surname,
  email,
  role,
  is_tp_member,
  verified,
  subscription,
  created_at
FROM profiles
WHERE role = 'member'
ORDER BY created_at DESC;
