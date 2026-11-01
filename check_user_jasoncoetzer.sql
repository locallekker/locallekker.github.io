-- Check all tables for jasoncoetzer@gmail.com / ec4436c6-461f-4c66-8ba6-0e8580306093
-- Run this in Supabase SQL Editor

DO $$
DECLARE
  target_user_id UUID := 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID;
  target_email TEXT := 'jasoncoetzer@gmail.com';
BEGIN
  RAISE NOTICE 'Checking all tables for user: % (%)', target_email, target_user_id;
  RAISE NOTICE '==============================================';
END $$;

-- Application Tables
SELECT 'profiles' as table_name, count(*) as records 
FROM profiles 
WHERE id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID OR email = 'jasoncoetzer@gmail.com'
UNION ALL
SELECT 'memberships', count(*) 
FROM memberships 
WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
UNION ALL
SELECT 'subscriptions', count(*) 
FROM subscriptions 
WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
UNION ALL
SELECT 'payments', count(*) 
FROM payments 
WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
UNION ALL
SELECT 'user_qr_codes', count(*) 
FROM user_qr_codes 
WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
UNION ALL
SELECT 'notifications', count(*) 
FROM notifications 
WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
UNION ALL
SELECT 'deal_authorizations', count(*) 
FROM deal_authorizations 
WHERE member_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
UNION ALL
SELECT 'processed_bills', count(*) 
FROM processed_bills 
WHERE member_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
UNION ALL
SELECT 'chat_messages', count(*) 
FROM chat_messages 
WHERE sender_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID

-- Auth Schema Tables
UNION ALL
SELECT 'auth.users', count(*) 
FROM auth.users 
WHERE id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID OR email = 'jasoncoetzer@gmail.com'
UNION ALL
SELECT 'auth.identities', count(*) 
FROM auth.identities 
WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
UNION ALL
SELECT 'auth.sessions', count(*) 
FROM auth.sessions 
WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
UNION ALL
SELECT 'auth.refresh_tokens', count(*) 
FROM auth.refresh_tokens 
WHERE user_id::text = 'ec4436c6-461f-4c66-8ba6-0e8580306093'
UNION ALL
SELECT 'auth.mfa_factors', count(*) 
FROM auth.mfa_factors 
WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
UNION ALL
SELECT 'auth.mfa_challenges', count(*) 
FROM auth.mfa_challenges 
WHERE factor_id IN (SELECT id FROM auth.mfa_factors WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID)
UNION ALL
SELECT 'auth.mfa_amr_claims', count(*) 
FROM auth.mfa_amr_claims 
WHERE session_id IN (SELECT id FROM auth.sessions WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID)
UNION ALL
SELECT 'auth.one_time_tokens', count(*) 
FROM auth.one_time_tokens 
WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
UNION ALL
SELECT 'auth.flow_state', count(*) 
FROM auth.flow_state 
WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
UNION ALL
SELECT 'auth.saml_relay_states', count(*) 
FROM auth.saml_relay_states 
WHERE flow_state_id IN (SELECT id FROM auth.flow_state WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID)
UNION ALL
SELECT 'auth.sso_providers', count(*) 
FROM auth.sso_providers 
WHERE resource_id IN (SELECT id::text FROM auth.identities WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID)

ORDER BY records DESC, table_name;

-- Show actual records from auth.users if any
SELECT 'auth.users records:' as info;
SELECT id, email, created_at, confirmed_at, email_confirmed_at, deleted_at
FROM auth.users 
WHERE id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID OR email = 'jasoncoetzer@gmail.com';

-- Show actual records from profiles if any
SELECT 'profiles records:' as info;
SELECT id, email, name, surname, created_at
FROM profiles 
WHERE id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID OR email = 'jasoncoetzer@gmail.com';

-- Show one-time tokens if any (these block signup)
SELECT 'auth.one_time_tokens records:' as info;
SELECT id, user_id, token_type, created_at, updated_at
FROM auth.one_time_tokens 
WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID;
