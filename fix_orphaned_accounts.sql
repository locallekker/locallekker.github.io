-- =====================================================
-- FIX ORPHANED AUTH ACCOUNTS
-- Create profiles for auth.users without profiles
-- =====================================================

-- First, let's see the orphaned accounts
SELECT 
  au.id,
  au.email,
  au.created_at,
  au.raw_user_meta_data,
  'Missing profile' as issue
FROM auth.users au
LEFT JOIN profiles p ON au.id = p.id
WHERE p.id IS NULL
ORDER BY au.created_at DESC;

-- Create profiles for orphaned auth accounts
-- This will insert profiles for any auth.users that don't have a profile
INSERT INTO profiles (
  id,
  email,
  name,
  surname,
  role,
  verified,
  created_at,
  updated_at
)
SELECT 
  au.id,
  au.email,
  COALESCE(au.raw_user_meta_data->>'name', au.email_confirmed_at::text, 'User') as name,
  COALESCE(au.raw_user_meta_data->>'surname', '') as surname,
  COALESCE(au.raw_user_meta_data->>'user_type', 
           au.raw_user_meta_data->>'role',
           'member') as role,
  true as verified, -- Default to verified for existing users
  au.created_at,
  NOW() as updated_at
FROM auth.users au
LEFT JOIN profiles p ON au.id = p.id
WHERE p.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- Create memberships for users without them
INSERT INTO memberships (
  user_id,
  role,
  gateway,
  created_at
)
SELECT 
  p.id,
  p.role,
  'auto_sync' as gateway,
  NOW()
FROM profiles p
LEFT JOIN memberships m ON p.id = m.user_id AND m.role = p.role
WHERE m.user_id IS NULL
  AND p.role IN ('member', 'trusted_partner');

-- For trusted partners without trusted_partners record
INSERT INTO trusted_partners (
  user_id,
  business_name,
  created_at
)
SELECT 
  p.id,
  COALESCE(p.name || '''s Business', 'Business') as business_name,
  NOW()
FROM profiles p
LEFT JOIN trusted_partners tp ON p.id = tp.user_id
WHERE p.role = 'trusted_partner'
  AND tp.user_id IS NULL;

-- Verify the fix
SELECT 
  'After sync - Total auth.users' as metric,
  COUNT(*)::text as value
FROM auth.users
UNION ALL
SELECT 
  'After sync - Total profiles',
  COUNT(*)::text
FROM profiles
UNION ALL
SELECT 
  'After sync - Total memberships',
  COUNT(*)::text
FROM memberships
UNION ALL
SELECT 
  'After sync - Members',
  COUNT(*)::text
FROM profiles WHERE role = 'member'
UNION ALL
SELECT 
  'After sync - TPs',
  COUNT(*)::text
FROM profiles WHERE role = 'trusted_partner'
UNION ALL
SELECT 
  'After sync - Orphaned auth accounts',
  COUNT(*)::text
FROM auth.users au
LEFT JOIN profiles p ON au.id = p.id
WHERE p.id IS NULL;
