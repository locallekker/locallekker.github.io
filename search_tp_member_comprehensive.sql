-- =====================================================
-- COMPREHENSIVE TP MEMBER SEARCH
-- Check if someone is both a TP and a member
-- =====================================================

-- Check trusted_partners table - maybe they ARE a TP who also registered as member
SELECT 
  'Trusted Partners' as search,
  tp.user_id,
  p.name,
  p.surname,
  p.email,
  p.role,
  tp.business_name,
  tp.unique_key,
  tp.created_at
FROM trusted_partners tp
LEFT JOIN profiles p ON tp.user_id = p.id
ORDER BY tp.created_at DESC;

-- Check if any TP has ALSO registered as a member (dual role scenario)
SELECT 
  'TPs with member memberships' as search,
  tp.user_id,
  p.name,
  p.surname,
  p.email,
  p.role as profile_role,
  m.role as membership_role,
  m.gateway,
  tp.business_name
FROM trusted_partners tp
INNER JOIN profiles p ON tp.user_id = p.id
LEFT JOIN memberships m ON tp.user_id = m.user_id AND m.role = 'member'
WHERE m.user_id IS NOT NULL;

-- Check QR codes with permanent expiry (indicator of TP member activation)
SELECT 
  'QR codes with 100-year expiry (TP member indicator)' as search,
  qr.user_id,
  p.name,
  p.surname,
  p.email,
  p.role,
  p.is_tp_member,
  qr.expires_at,
  qr.is_active,
  qr.created_at
FROM user_qr_codes qr
LEFT JOIN profiles p ON qr.user_id = p.id
WHERE qr.expires_at > NOW() + INTERVAL '50 years'
ORDER BY qr.created_at DESC;
