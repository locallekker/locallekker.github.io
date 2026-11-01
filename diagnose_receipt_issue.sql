-- Comprehensive diagnostic for receipt generation issue
-- Run this to check EVERYTHING

-- 1. Check most recent deal authorization for clydemfaln@gmail.com
SELECT 
  'RECENT DEAL' as check_type,
  da.id,
  da.member_id,
  da.trusted_partner_id,
  da.amount,
  da.approved_at,
  da.payment_completed_at,
  da.completed_at,
  da.created_at,
  p.email as member_email
FROM deal_authorizations da
JOIN profiles p ON da.member_id = p.id
WHERE p.email = 'clydemfaln@gmail.com'
ORDER BY da.created_at DESC
LIMIT 1;

-- 2. Check if ANY receipts exist for this member
SELECT 
  'VIRTUAL RECEIPTS' as check_type,
  COUNT(*) as total_receipts
FROM virtual_receipts vr
JOIN deal_authorizations da ON vr.deal_authorization_id = da.id
JOIN profiles p ON da.member_id = p.id
WHERE p.email = 'clydemfaln@gmail.com';

-- 3. Check deal_receipts table
SELECT 
  'DEAL RECEIPTS' as check_type,
  COUNT(*) as total_receipts
FROM deal_receipts dr
JOIN profiles p ON dr.member_id = p.id
WHERE p.email = 'clydemfaln@gmail.com';

-- 4. Check ALL RLS policies on critical tables
SELECT 
  'RLS POLICIES' as check_type,
  tablename,
  policyname,
  cmd,
  permissive,
  CASE 
    WHEN qual IS NULL THEN 'NO USING CLAUSE'
    ELSE 'HAS USING'
  END as using_check,
  CASE 
    WHEN with_check IS NULL THEN 'NO WITH CHECK'
    ELSE 'HAS WITH CHECK'
  END as with_check_status
FROM pg_policies
WHERE tablename IN ('deal_authorizations', 'virtual_receipts', 'deal_receipts')
ORDER BY tablename, cmd;

-- 5. Check if get_next_receipt_number function exists
SELECT 
  'FUNCTION CHECK' as check_type,
  proname as function_name,
  pg_get_function_arguments(oid) as arguments
FROM pg_proc
WHERE proname = 'get_next_receipt_number';

-- 6. Get the actual member_id for clydemfaln@gmail.com
SELECT 
  'MEMBER ID' as check_type,
  id as member_id,
  email,
  name,
  surname,
  role
FROM profiles
WHERE email = 'clydemfaln@gmail.com';

-- 7. Check if there are any receipts at all in the system (from any user)
SELECT 
  'SYSTEM RECEIPTS' as check_type,
  (SELECT COUNT(*) FROM virtual_receipts) as total_virtual_receipts,
  (SELECT COUNT(*) FROM deal_receipts) as total_deal_receipts;
