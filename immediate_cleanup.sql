-- IMMEDIATE FIX: Clean up orphaned clydemfaln profile
-- Run this NOW in Supabase SQL Editor

-- Delete the orphaned profile and membership
DELETE FROM public.memberships
WHERE user_id IN (
    SELECT id FROM public.profiles
    WHERE email ILIKE '%clydemfaln%'
    AND id NOT IN (SELECT id FROM auth.users)
);

DELETE FROM public.profiles
WHERE email ILIKE '%clydemfaln%'
AND id NOT IN (SELECT id FROM auth.users);

-- Verify cleanup
SELECT 'REMAINING_PROFILES' as check, COUNT(*) as count
FROM public.profiles
WHERE email ILIKE '%clydemfaln%';

SELECT 'REMAINING_AUTH_USERS' as check, COUNT(*) as count
FROM auth.users
WHERE email ILIKE '%clydemfaln%';