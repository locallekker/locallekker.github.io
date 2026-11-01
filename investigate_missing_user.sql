-- Investigation: User not found in profiles table
-- Run this in Supabase SQL Editor to find the actual issue

-- 1. Check if the user exists in ANY table
SELECT 'Checking all tables for user ID 736ac25c-5e0b-45af-a3f0-c670c11aa222:' as investigation;

SELECT 'profiles' as table_name, COUNT(*) as record_count
FROM profiles WHERE id = '736ac25c-5e0b-45af-a3f0-c670c11aa222'
UNION ALL
SELECT 'trusted_partners' as table_name, COUNT(*) as record_count
FROM trusted_partners WHERE user_id = '736ac25c-5e0b-45af-a3f0-c670c11aa222'
UNION ALL
SELECT 'memberships' as table_name, COUNT(*) as record_count
FROM memberships WHERE user_id = '736ac25c-5e0b-45af-a3f0-c670c11aa222'
UNION ALL
SELECT 'auth.users' as table_name, COUNT(*) as record_count
FROM auth.users WHERE id = '736ac25c-5e0b-45af-a3f0-c670c11aa222';

-- 2. List all current trusted partners to see what's actually in the system
SELECT 'Current trusted partners in the system:' as info;

SELECT
    p.id,
    p.email,
    p.name,
    p.surname,
    p.role,
    p.admin_created,
    p.password_set,
    tp.business_name,
    tp.created_at as tp_created
FROM trusted_partners tp
JOIN profiles p ON tp.user_id = p.id
ORDER BY tp.created_at DESC;

-- 3. Check for orphaned records (trusted_partners without matching profiles)
SELECT 'Orphaned trusted_partners records (no matching profile):' as orphaned_check;

SELECT
    tp.user_id,
    tp.business_name,
    tp.created_at
FROM trusted_partners tp
LEFT JOIN profiles p ON tp.user_id = p.id
WHERE p.id IS NULL;

-- 4. Check for orphaned profiles (trusted_partner role but no trusted_partners record)
SELECT 'Orphaned profiles (trusted_partner role but no trusted_partners record):' as orphaned_profiles;

SELECT
    p.id,
    p.email,
    p.name,
    p.role,
    p.admin_created,
    p.password_set
FROM profiles p
LEFT JOIN trusted_partners tp ON tp.user_id = p.id
WHERE p.role = 'trusted_partner' AND tp.user_id IS NULL;

-- 5. If you want to clean up orphaned trusted_partners records, uncomment and run:
-- DELETE FROM trusted_partners WHERE user_id NOT IN (SELECT id FROM profiles WHERE role = 'trusted_partner');