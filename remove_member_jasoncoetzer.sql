-- Remove all data for jasoncoetzer@gmail.com to allow fresh signup
-- Run this in Supabase SQL Editor as postgres/service_role

-- STEP 1: Temporarily disable RLS for easier deletion
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions DISABLE ROW LEVEL SECURITY;
ALTER TABLE memberships DISABLE ROW LEVEL SECURITY;
ALTER TABLE payments DISABLE ROW LEVEL SECURITY;
ALTER TABLE user_qr_codes DISABLE ROW LEVEL SECURITY;
ALTER TABLE notifications DISABLE ROW LEVEL SECURITY;
ALTER TABLE deal_authorizations DISABLE ROW LEVEL SECURITY;
ALTER TABLE processed_bills DISABLE ROW LEVEL SECURITY;

-- STEP 2: Delete all user data
DO $$
DECLARE
  target_user_id UUID := 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID;
BEGIN
  RAISE NOTICE 'Removing all data for user: %', target_user_id;

  -- Delete from child tables first (to respect foreign keys)
  
  -- Delete notifications
  DELETE FROM notifications WHERE user_id = target_user_id;
  RAISE NOTICE 'Deleted notifications';

  -- Delete deal authorizations
  DELETE FROM deal_authorizations WHERE member_id = target_user_id;
  RAISE NOTICE 'Deleted deal authorizations';

  -- Delete processed bills
  DELETE FROM processed_bills WHERE member_id = target_user_id;
  RAISE NOTICE 'Deleted processed bills';

  -- Delete user QR codes
  DELETE FROM user_qr_codes WHERE user_id = target_user_id;
  RAISE NOTICE 'Deleted QR codes';

  -- Delete payments
  DELETE FROM payments WHERE user_id = target_user_id;
  RAISE NOTICE 'Deleted payments';

  -- Delete subscriptions
  DELETE FROM subscriptions WHERE user_id = target_user_id;
  RAISE NOTICE 'Deleted subscriptions';

  -- Delete memberships
  DELETE FROM memberships WHERE user_id = target_user_id;
  RAISE NOTICE 'Deleted memberships';

  -- Delete chat messages (if exists)
  DELETE FROM chat_messages WHERE sender_id = target_user_id;
  RAISE NOTICE 'Deleted chat messages';

  -- Delete from profiles (main user profile)
  DELETE FROM profiles WHERE id = target_user_id OR email = 'jasoncoetzer@gmail.com';
  RAISE NOTICE 'Deleted profile';

  -- Clean up all auth schema tables (delete in correct order)
  
  -- Delete MFA-related records first
  DELETE FROM auth.mfa_amr_claims WHERE session_id IN (
    SELECT id FROM auth.sessions WHERE user_id = target_user_id
  );
  RAISE NOTICE 'Deleted mfa_amr_claims';
  
  DELETE FROM auth.mfa_challenges WHERE factor_id IN (
    SELECT id FROM auth.mfa_factors WHERE user_id = target_user_id
  );
  RAISE NOTICE 'Deleted auth mfa_challenges';

  DELETE FROM auth.mfa_factors WHERE user_id = target_user_id;
  RAISE NOTICE 'Deleted auth mfa_factors';

  -- Delete session-related records
  DELETE FROM auth.refresh_tokens WHERE user_id::text = target_user_id::text;
  RAISE NOTICE 'Deleted auth refresh tokens';

  DELETE FROM auth.sessions WHERE user_id = target_user_id;
  RAISE NOTICE 'Deleted auth sessions';

  -- Delete flow state and SAML records
  DELETE FROM auth.saml_relay_states WHERE flow_state_id IN (
    SELECT id FROM auth.flow_state WHERE user_id = target_user_id
  );
  RAISE NOTICE 'Deleted saml_relay_states';

  DELETE FROM auth.flow_state WHERE user_id = target_user_id;
  RAISE NOTICE 'Deleted flow_state';

  -- Delete SSO records (with proper type casting)
  DELETE FROM auth.saml_providers WHERE sso_provider_id IN (
    SELECT id FROM auth.sso_providers WHERE resource_id IN (
      SELECT id::text FROM auth.identities WHERE user_id = target_user_id
    )
  );
  RAISE NOTICE 'Deleted saml_providers';

  DELETE FROM auth.sso_domains WHERE sso_provider_id IN (
    SELECT id FROM auth.sso_providers WHERE resource_id IN (
      SELECT id::text FROM auth.identities WHERE user_id = target_user_id
    )
  );
  RAISE NOTICE 'Deleted sso_domains';

  DELETE FROM auth.sso_providers WHERE resource_id IN (
    SELECT id::text FROM auth.identities WHERE user_id = target_user_id
  );
  RAISE NOTICE 'Deleted sso_providers';

  -- Delete identities
  DELETE FROM auth.identities WHERE user_id = target_user_id;
  RAISE NOTICE 'Deleted auth identities';

  -- Delete one-time tokens (email confirmations, password reset, etc.)
  DELETE FROM auth.one_time_tokens WHERE user_id = target_user_id;
  RAISE NOTICE 'Deleted one_time_tokens';

  -- Finally delete the auth user
  DELETE FROM auth.users WHERE id = target_user_id OR email = 'jasoncoetzer@gmail.com';
  RAISE NOTICE 'Deleted auth user';

  RAISE NOTICE 'Successfully removed all data for jasoncoetzer@gmail.com';
END $$;

-- STEP 3: Re-enable RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_qr_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE deal_authorizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE processed_bills ENABLE ROW LEVEL SECURITY;

-- Confirm deletion
SELECT 'User still exists in auth.users' as status WHERE EXISTS (
  SELECT 1 FROM auth.users WHERE email = 'jasoncoetzer@gmail.com'
)
UNION ALL
SELECT 'User still exists in profiles' WHERE EXISTS (
  SELECT 1 FROM profiles WHERE email = 'jasoncoetzer@gmail.com'
)
UNION ALL
SELECT 'One-time tokens still exist' WHERE EXISTS (
  SELECT 1 FROM auth.one_time_tokens WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
)
UNION ALL
SELECT 'Identities still exist' WHERE EXISTS (
  SELECT 1 FROM auth.identities WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
)
UNION ALL
SELECT 'User successfully deleted - ready for fresh signup' WHERE NOT EXISTS (
  SELECT 1 FROM auth.users WHERE email = 'jasoncoetzer@gmail.com'
) AND NOT EXISTS (
  SELECT 1 FROM profiles WHERE email = 'jasoncoetzer@gmail.com'
) AND NOT EXISTS (
  SELECT 1 FROM auth.identities WHERE user_id = 'ec4436c6-461f-4c66-8ba6-0e8580306093'::UUID
);
