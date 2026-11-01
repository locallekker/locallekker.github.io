-- Fix orphaned trusted partner profiles
-- Run this in Supabase SQL Editor

-- 1. First, let's see what orphaned profiles we have
SELECT 'Orphaned trusted partner profiles to fix:' as info;

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

-- 2. For each orphaned profile, we need to either:
-- Option A: Create the missing trusted_partners record (if they should be TPs)
-- Option B: Change their role back to 'member' (if they shouldn't be TPs)

-- Option A: Create trusted_partners records for orphaned profiles
-- Uncomment and modify the business_name for each user:
/*
INSERT INTO trusted_partners (user_id, business_name, created_at)
SELECT
    p.id,
    'Business Name Here - ' || p.name,  -- Modify business name as needed
    NOW()
FROM profiles p
LEFT JOIN trusted_partners tp ON tp.user_id = p.id
WHERE p.role = 'trusted_partner' AND tp.user_id IS NULL;
*/

-- Option B: Change orphaned trusted partners back to members
-- Uncomment to fix the role:
/*
UPDATE profiles
SET role = 'member', updated_at = NOW()
WHERE id IN (
    SELECT p.id
    FROM profiles p
    LEFT JOIN trusted_partners tp ON tp.user_id = p.id
    WHERE p.role = 'trusted_partner' AND tp.user_id IS NULL
);
*/

-- 3. Check the specific user thecraftsmanel@gmail.com
SELECT 'Checking thecraftsmanel@gmail.com:' as specific_user;

SELECT
    p.id,
    p.email,
    p.name,
    p.role,
    p.admin_created,
    p.password_set,
    CASE WHEN tp.user_id IS NOT NULL THEN 'Has trusted_partners record' ELSE 'Orphaned - no trusted_partners record' END as status
FROM profiles p
LEFT JOIN trusted_partners tp ON tp.user_id = p.id
WHERE p.email = 'thecraftsmanel@gmail.com';