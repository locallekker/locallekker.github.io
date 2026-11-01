-- Clear all receipt and deal authorization data for clydemflan@gmail.com and houselillian5@gmail.com
-- This will allow starting fresh with new deals and receipts to verify savings calculations

-- Step 1: Get user IDs
WITH user_info AS (
  SELECT id, email
  FROM profiles
  WHERE email IN ('clydemflan@gmail.com', 'houselillian5@gmail.com')
)
SELECT id, email FROM user_info;

-- Step 2: Check what will be deleted (run this first to verify)
WITH user_info AS (
  SELECT id as user_id
  FROM profiles
  WHERE email IN ('clydemflan@gmail.com', 'houselillian5@gmail.com')
)
SELECT 
  'deal_receipts' as table_name,
  COUNT(*) as records_to_delete
FROM deal_receipts
WHERE member_id IN (SELECT user_id FROM user_info)
UNION ALL
SELECT 
  'virtual_receipts' as table_name,
  COUNT(*) as records_to_delete
FROM virtual_receipts vr
WHERE vr.deal_authorization_id IN (
  SELECT da.id 
  FROM deal_authorizations da 
  WHERE da.member_id IN (SELECT user_id FROM user_info)
)
UNION ALL
SELECT 
  'deal_authorizations' as table_name,
  COUNT(*) as records_to_delete
FROM deal_authorizations
WHERE member_id IN (SELECT user_id FROM user_info);

-- Step 3: DELETE deal_receipts (this will cascade to related data if foreign keys are set up)
-- Run this after verifying the counts above
WITH user_info AS (
  SELECT id as user_id
  FROM profiles
  WHERE email IN ('clydemflan@gmail.com', 'houselillian5@gmail.com')
)
DELETE FROM deal_receipts
WHERE member_id IN (SELECT user_id FROM user_info);

-- Step 4: DELETE virtual_receipts (must delete before deal_authorizations due to foreign key)
WITH user_info AS (
  SELECT id as user_id
  FROM profiles
  WHERE email IN ('clydemflan@gmail.com', 'houselillian5@gmail.com')
)
DELETE FROM virtual_receipts
WHERE deal_authorization_id IN (
  SELECT da.id 
  FROM deal_authorizations da 
  WHERE da.member_id IN (SELECT user_id FROM user_info)
);

-- Step 5: DELETE deal_authorizations (after virtual_receipts are deleted)
WITH user_info AS (
  SELECT id as user_id
  FROM profiles
  WHERE email IN ('clydemflan@gmail.com', 'houselillian5@gmail.com')
)
DELETE FROM deal_authorizations
WHERE member_id IN (SELECT user_id FROM user_info);

-- Step 6: Verify deletion
WITH user_info AS (
  SELECT id as user_id
  FROM profiles
  WHERE email IN ('clydemflan@gmail.com', 'houselillian5@gmail.com')
)
SELECT 
  'deal_receipts' as table_name,
  COUNT(*) as remaining_records
FROM deal_receipts
WHERE member_id IN (SELECT user_id FROM user_info)
UNION ALL
SELECT 
  'virtual_receipts' as table_name,
  COUNT(*) as remaining_records
FROM virtual_receipts vr
WHERE vr.deal_authorization_id IN (
  SELECT da.id 
  FROM deal_authorizations da 
  WHERE da.member_id IN (SELECT user_id FROM user_info)
)
UNION ALL
SELECT 
  'deal_authorizations' as table_name,
  COUNT(*) as remaining_records
FROM deal_authorizations
WHERE member_id IN (SELECT user_id FROM user_info);

-- Step 7: Verify profiles and subscriptions are intact
SELECT 
  p.email,
  p.name,
  p.surname,
  s.status as subscription_status,
  s.current_period_end,
  uqr.is_active as qr_active
FROM profiles p
LEFT JOIN subscriptions s ON p.id = s.user_id
LEFT JOIN user_qr_codes uqr ON p.id = uqr.user_id
WHERE p.email IN ('clydemflan@gmail.com', 'houselillian5@gmail.com')
ORDER BY p.email;
