-- =====================================================
-- SYNC VERIFIED STATUS WITH SUBSCRIPTION STATUS
-- Updates profiles.verified based on profiles.subscription
-- =====================================================

-- Show current mismatch
SELECT 
  'Before sync - Mismatched records' as check_type,
  COUNT(*) as count
FROM profiles
WHERE 
  role = 'member' 
  AND (
    (subscription = 'pending' AND verified = true) OR
    (subscription = 'active' AND verified = false)
  );

-- Update members based on subscription status
-- Active subscription = verified true
-- Pending subscription = verified false
UPDATE profiles
SET 
  verified = CASE 
    WHEN subscription = 'active' THEN true
    WHEN subscription = 'pending' THEN false
    ELSE verified  -- Keep current value if no subscription
  END,
  updated_at = NOW()
WHERE 
  role = 'member'
  AND subscription IS NOT NULL;

-- For trusted partners, check if they have completed business setup
-- Completed = verified true, Incomplete = verified false
UPDATE profiles
SET 
  verified = CASE 
    WHEN EXISTS (
      SELECT 1 
      FROM businesses b 
      WHERE b.owner_member_id = profiles.id 
        AND b.name IS NOT NULL 
        AND b.name != '' 
        AND b.contact_number IS NOT NULL
    )
    AND EXISTS (
      SELECT 1
      FROM trusted_partners tp
      WHERE tp.user_id = profiles.id
        AND tp.business_name IS NOT NULL
    )
    THEN true
    ELSE false
  END,
  updated_at = NOW()
WHERE 
  role = 'trusted_partner';

-- Verify the sync results
SELECT 
  'After sync - Members by status' as metric,
  subscription as subscription_status,
  verified as profile_verified,
  COUNT(*) as count
FROM profiles
WHERE role = 'member'
GROUP BY subscription, verified
ORDER BY subscription, verified;

SELECT 
  'After sync - TPs by status' as metric,
  CASE 
    WHEN b.id IS NOT NULL AND b.name IS NOT NULL THEN 'completed'
    ELSE 'incomplete'
  END as business_setup,
  p.verified as profile_verified,
  COUNT(*) as count
FROM profiles p
INNER JOIN trusted_partners tp ON p.id = tp.user_id
LEFT JOIN businesses b ON b.owner_member_id = p.id
WHERE p.role = 'trusted_partner'
GROUP BY business_setup, p.verified
ORDER BY business_setup, p.verified;

-- Summary counts for admin screens
SELECT 
  'Members verified' as metric,
  COUNT(*) as count
FROM profiles
WHERE role = 'member' AND verified = true
UNION ALL
SELECT 
  'Members pending',
  COUNT(*)
FROM profiles
WHERE role = 'member' AND verified = false
UNION ALL
SELECT 
  'TPs verified',
  COUNT(*)
FROM profiles
WHERE role = 'trusted_partner' AND verified = true
UNION ALL
SELECT 
  'TPs pending',
  COUNT(*)
FROM profiles
WHERE role = 'trusted_partner' AND verified = false;
