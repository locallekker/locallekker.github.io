-- DELETE TP: micheleshein01@gmail.com (id: c3b07fbe-8755-4848-af4f-9a40d0c38fcc)
-- Run each block in order in the Supabase SQL editor

DO $$
DECLARE
  v_user_id UUID := 'c3b07fbe-8755-4848-af4f-9a40d0c38fcc';
BEGIN
  -- 1. Notifications
  DELETE FROM public.notifications WHERE user_id = v_user_id;

  -- 2. Deal authorizations linked to this TP's discounts
  DELETE FROM public.deal_authorizations
  WHERE discount_id IN (
    SELECT id FROM public.trusted_partner_discounts WHERE trusted_partner_id = v_user_id
  );

  -- 3. TP discounts / deals
  DELETE FROM public.trusted_partner_discounts WHERE trusted_partner_id = v_user_id;

  -- 4. Bank accounts
  DELETE FROM public.trusted_partner_bank_accounts WHERE trusted_partner_id = v_user_id;

  -- 5. Businesses owned by this TP
  DELETE FROM public.businesses WHERE owner_member_id = v_user_id;

  -- 6. Trusted partner record
  DELETE FROM public.trusted_partners WHERE user_id = v_user_id;

  -- 7. Profile
  DELETE FROM public.profiles WHERE id = v_user_id;

  -- 8. Auth user (must be last)
  DELETE FROM auth.users WHERE id = v_user_id;

  RAISE NOTICE 'User % deleted successfully', v_user_id;
END $$;

-- Search ALL tables for the target emails
-- Run in Supabase SQL editor (requires postgres / service role)

-- 1. auth.users
SELECT 'auth.users' AS source, id, email, created_at, last_sign_in_at
FROM auth.users
WHERE email IN ('coetzer246@spfamily.co.za', 'fuelbean@gmail.com');

-- 2. profiles name/surname search
SELECT 'profiles' AS source, id, name, surname, role, created_at
FROM public.profiles
WHERE name ILIKE '%coetzer%' OR surname ILIKE '%coetzer%'
   OR name ILIKE '%michele%' OR name ILIKE '%ryan%';

-- 3. trusted_partners joined with auth.users for email
SELECT 'trusted_partners' AS source, tp.user_id, au.email, tp.business_name, tp.created_at
FROM public.trusted_partners tp
JOIN auth.users au ON au.id = tp.user_id
WHERE au.email IN ('coetzer246@spfamily.co.za', 'fuelbean@gmail.com');

-- 4. businesses joined with auth.users for email
SELECT 'businesses' AS source, b.id, b.name, au.email, b.created_at
FROM public.businesses b
JOIN auth.users au ON au.id = b.owner_member_id
WHERE au.email IN ('coetzer246@spfamily.co.za', 'fuelbean@gmail.com');

-- 5. Broad name search with auth email joined
SELECT 'profiles_name_search' AS source, p.id, au.email, p.name, p.surname, p.role, p.created_at
FROM public.profiles p
JOIN auth.users au ON au.id = p.id
WHERE p.name ILIKE '%coetzer%'
   OR p.surname ILIKE '%coetzer%'
   OR p.name ILIKE '%michele%'
   OR p.name ILIKE '%ryan%'
ORDER BY p.created_at DESC;
