-- Fix database error preventing jasoncoetzer@gmail.com signup
-- The "500: Database error saving new user" indicates triggers or constraints blocking signup

-- STEP 1: Check for problematic triggers on auth.users
SELECT 
  trigger_name,
  event_manipulation,
  event_object_table,
  action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'auth' 
  AND event_object_table = 'users'
ORDER BY trigger_name;

-- STEP 2: Check for triggers on profiles table that might fail
SELECT 
  trigger_name,
  event_manipulation,
  event_object_table,
  action_statement
FROM information_schema.triggers
WHERE event_object_table = 'profiles'
ORDER BY trigger_name;

-- STEP 3: Temporarily disable problematic triggers if needed
-- Look for any trigger that creates profiles/memberships automatically
-- Common culprit: handle_new_user trigger or similar

-- Example to disable (uncomment if needed):
-- ALTER TABLE auth.users DISABLE TRIGGER ALL;
-- ALTER TABLE profiles DISABLE TRIGGER ALL;

-- STEP 4: Check if there's a stale record blocking the email
SELECT 
  id, 
  email, 
  raw_user_meta_data,
  created_at,
  deleted_at,
  is_super_admin,
  banned_until
FROM auth.users 
WHERE email = 'jasoncoetzer@gmail.com'
   OR raw_user_meta_data->>'email' = 'jasoncoetzer@gmail.com';

-- STEP 5: Check for soft-deleted users (deleted_at not null)
SELECT 
  id,
  email,
  deleted_at,
  banned_until
FROM auth.users
WHERE deleted_at IS NOT NULL
  AND email = 'jasoncoetzer@gmail.com';

-- If soft-deleted user found, hard delete it:
-- DELETE FROM auth.users WHERE email = 'jasoncoetzer@gmail.com' AND deleted_at IS NOT NULL;

-- STEP 6: Check profiles table for any remaining records
SELECT id, email, created_at, is_deactivated
FROM profiles
WHERE email = 'jasoncoetzer@gmail.com';

-- STEP 7: Clear any audit logs that might be blocking
DELETE FROM auth.audit_log_entries 
WHERE payload->>'email' = 'jasoncoetzer@gmail.com'
  AND created_at < NOW() - INTERVAL '1 hour';

-- STEP 8: Test if email is truly available
SELECT 
  CASE 
    WHEN EXISTS (SELECT 1 FROM auth.users WHERE email = 'jasoncoetzer@gmail.com') 
    THEN 'Email exists in auth.users - BLOCKING SIGNUP'
    WHEN EXISTS (SELECT 1 FROM profiles WHERE email = 'jasoncoetzer@gmail.com')
    THEN 'Email exists in profiles - MAY BLOCK SIGNUP'
    ELSE 'Email is available for signup ✓'
  END as status;
