-- Fix for clydemfaln sign-in issue
-- The profile exists but auth user doesn't - this is an orphaned profile

-- STEP 1: Check if subscription column exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'profiles'
        AND column_name = 'subscription'
    ) THEN
        -- Add subscription column if it doesn't exist
        ALTER TABLE public.profiles ADD COLUMN subscription TEXT DEFAULT 'pending';
        RAISE NOTICE 'Added subscription column to profiles table';
    ELSE
        RAISE NOTICE 'Subscription column already exists';
    END IF;
END $$;

-- STEP 2: Show current clydemfaln profile data
SELECT
    'CURRENT_PROFILE' as status,
    id, email, name, surname, role, category, in_app_password, subscription,
    created_at, updated_at
FROM public.profiles
WHERE email ILIKE '%clydemfaln%' OR name ILIKE '%clydemfaln%' OR surname ILIKE '%clydemfaln%';

-- STEP 3: Check if auth user exists
SELECT
    'AUTH_USER_CHECK' as status,
    COUNT(*) as auth_users_found
FROM auth.users
WHERE email ILIKE '%clydemfaln%';

-- STEP 4: CLEANUP - Remove orphaned profile and membership
-- (Only run this if you want to clean up and have user sign up again)
-- DELETE FROM public.memberships WHERE user_id IN (
--     SELECT id FROM public.profiles
--     WHERE email ILIKE '%clydemfaln%'
--     AND id NOT IN (SELECT id FROM auth.users)
-- );
--
-- DELETE FROM public.profiles
-- WHERE email ILIKE '%clydemfaln%'
-- AND id NOT IN (SELECT id FROM auth.users);

-- STEP 5: Alternative - Create auth user entry (NOT RECOMMENDED - auth users must be created through Supabase Auth)
-- This cannot be done through SQL. Auth users must be created through the signup process.