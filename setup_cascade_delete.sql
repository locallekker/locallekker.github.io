-- =====================================================
-- CASCADE DELETE SETUP FOR USER DELETION
-- =====================================================
-- This script ensures that when a user is deleted from 
-- auth.users, all their related data is automatically 
-- deleted from profiles, memberships, and user_qr_codes
-- =====================================================

-- Step 1: Drop existing foreign key constraints if they exist
-- (We need to recreate them with ON DELETE CASCADE)

-- Drop foreign key on profiles table
ALTER TABLE IF EXISTS public.profiles 
DROP CONSTRAINT IF EXISTS profiles_id_fkey;

-- Drop foreign key on memberships table (if it exists)
ALTER TABLE IF EXISTS public.memberships 
DROP CONSTRAINT IF EXISTS memberships_user_id_fkey;

-- Drop foreign key on user_qr_codes table
ALTER TABLE IF EXISTS public.user_qr_codes 
DROP CONSTRAINT IF EXISTS user_qr_codes_user_id_fkey;

-- Drop foreign key on subscriptions table
ALTER TABLE IF EXISTS public.subscriptions 
DROP CONSTRAINT IF EXISTS subscriptions_user_id_fkey;

-- Drop foreign key on subscription_renewals table (if exists)
ALTER TABLE IF EXISTS public.subscription_renewals 
DROP CONSTRAINT IF EXISTS subscription_renewals_user_id_fkey;

-- =====================================================
-- Step 2: Add foreign keys WITH CASCADE DELETE
-- =====================================================

-- Add CASCADE DELETE to profiles table
-- When user deleted from auth.users -> delete profile
ALTER TABLE public.profiles
ADD CONSTRAINT profiles_id_fkey 
FOREIGN KEY (id) 
REFERENCES auth.users(id) 
ON DELETE CASCADE;

-- Add CASCADE DELETE to memberships table
-- When user deleted from auth.users -> delete membership
ALTER TABLE public.memberships
ADD CONSTRAINT memberships_user_id_fkey 
FOREIGN KEY (user_id) 
REFERENCES auth.users(id) 
ON DELETE CASCADE;

-- Add CASCADE DELETE to user_qr_codes table
-- When user deleted from auth.users -> delete QR codes
ALTER TABLE public.user_qr_codes
ADD CONSTRAINT user_qr_codes_user_id_fkey 
FOREIGN KEY (user_id) 
REFERENCES auth.users(id) 
ON DELETE CASCADE;

-- Add CASCADE DELETE to subscriptions table
-- When user deleted from auth.users -> delete subscriptions
ALTER TABLE public.subscriptions
ADD CONSTRAINT subscriptions_user_id_fkey 
FOREIGN KEY (user_id) 
REFERENCES auth.users(id) 
ON DELETE CASCADE;

-- Add CASCADE DELETE to subscription_renewals table
-- When user deleted from auth.users -> delete renewal records
ALTER TABLE public.subscription_renewals
ADD CONSTRAINT subscription_renewals_user_id_fkey 
FOREIGN KEY (user_id) 
REFERENCES auth.users(id) 
ON DELETE CASCADE;

-- =====================================================
-- Step 3: Verify foreign key constraints
-- =====================================================

-- Check profiles foreign key
SELECT 
    'profiles' as table_name,
    conname as constraint_name,
    confdeltype as delete_action
FROM pg_constraint
WHERE conrelid = 'public.profiles'::regclass
AND conname LIKE '%fkey%'
AND confdeltype = 'c'; -- 'c' = CASCADE

-- Check memberships foreign key
SELECT 
    'memberships' as table_name,
    conname as constraint_name,
    confdeltype as delete_action
FROM pg_constraint
WHERE conrelid = 'public.memberships'::regclass
AND conname LIKE '%user_id_fkey%'
AND confdeltype = 'c';

-- Check user_qr_codes foreign key
SELECT 
    'user_qr_codes' as table_name,
    conname as constraint_name,
    confdeltype as delete_action
FROM pg_constraint
WHERE conrelid = 'public.user_qr_codes'::regclass
AND conname LIKE '%user_id_fkey%'
AND confdeltype = 'c';

-- Check subscriptions foreign key
SELECT 
    'subscriptions' as table_name,
    conname as constraint_name,
    confdeltype as delete_action
FROM pg_constraint
WHERE conrelid = 'public.subscriptions'::regclass
AND conname LIKE '%user_id_fkey%'
AND confdeltype = 'c';

-- Check subscription_renewals foreign key
SELECT 
    'subscription_renewals' as table_name,
    conname as constraint_name,
    confdeltype as delete_action
FROM pg_constraint
WHERE conrelid = 'public.subscription_renewals'::regclass
AND conname LIKE '%user_id_fkey%'
AND confdeltype = 'c';

-- =====================================================
-- Step 4: Test CASCADE DELETE (commented out)
-- =====================================================
-- IMPORTANT: Uncomment these lines ONLY for testing!
-- Replace 'test-user-id-here' with an actual test user ID

/*
-- Create test user to verify cascade delete works
DO $$
DECLARE
    test_user_id uuid;
BEGIN
    -- Insert test user into auth.users (you may need admin access)
    -- This is just for testing - normally users are created via Supabase Auth
    
    -- Verify cascade works by checking counts before and after delete
    RAISE NOTICE 'Before delete:';
    RAISE NOTICE 'Profiles count for user: %', (SELECT COUNT(*) FROM profiles WHERE id = 'test-user-id-here');
    RAISE NOTICE 'Memberships count for user: %', (SELECT COUNT(*) FROM memberships WHERE user_id = 'test-user-id-here');
    RAISE NOTICE 'QR codes count for user: %', (SELECT COUNT(*) FROM user_qr_codes WHERE user_id = 'test-user-id-here');
    RAISE NOTICE 'Subscriptions count for user: %', (SELECT COUNT(*) FROM subscriptions WHERE user_id = 'test-user-id-here');
    
    -- Delete user from auth.users (this should cascade to all related tables)
    -- DELETE FROM auth.users WHERE id = 'test-user-id-here';
    
    RAISE NOTICE 'After delete:';
    RAISE NOTICE 'Profiles count for user: %', (SELECT COUNT(*) FROM profiles WHERE id = 'test-user-id-here');
    RAISE NOTICE 'Memberships count for user: %', (SELECT COUNT(*) FROM memberships WHERE user_id = 'test-user-id-here');
    RAISE NOTICE 'QR codes count for user: %', (SELECT COUNT(*) FROM user_qr_codes WHERE user_id = 'test-user-id-here');
    RAISE NOTICE 'Subscriptions count for user: %', (SELECT COUNT(*) FROM subscriptions WHERE user_id = 'test-user-id-here');
END $$;
*/

-- =====================================================
-- USAGE NOTES
-- =====================================================
-- 
-- After running this script:
-- 1. When a user is deleted via Supabase Dashboard -> Authentication -> Users -> Delete
-- 2. OR when auth.signOut() is called followed by user deletion
-- 3. OR when DELETE FROM auth.users WHERE id = 'user-id' is executed
-- 
-- All of the following will be AUTOMATICALLY deleted:
-- - profiles.id = user_id
-- - memberships.user_id = user_id
-- - user_qr_codes.user_id = user_id
-- - subscriptions.user_id = user_id
-- - subscription_renewals.user_id = user_id
-- 
-- This ensures no orphaned records remain in the database.
-- =====================================================

COMMENT ON CONSTRAINT profiles_id_fkey ON public.profiles 
IS 'CASCADE DELETE: When user deleted from auth.users, delete profile';

COMMENT ON CONSTRAINT memberships_user_id_fkey ON public.memberships 
IS 'CASCADE DELETE: When user deleted from auth.users, delete membership';

COMMENT ON CONSTRAINT user_qr_codes_user_id_fkey ON public.user_qr_codes 
IS 'CASCADE DELETE: When user deleted from auth.users, delete QR codes';

COMMENT ON CONSTRAINT subscriptions_user_id_fkey ON public.subscriptions 
IS 'CASCADE DELETE: When user deleted from auth.users, delete subscriptions';

COMMENT ON CONSTRAINT subscription_renewals_user_id_fkey ON public.subscription_renewals 
IS 'CASCADE DELETE: When user deleted from auth.users, delete renewal records';

-- =====================================================
-- End of script
-- =====================================================
