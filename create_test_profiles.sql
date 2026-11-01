-- Check if the test users have profiles
SELECT '=== CHECKING TEST MEMBER PROFILES ===' as info;
SELECT
    'Member 1 (houselillian5@gmail.com)' as member_check,
    CASE WHEN EXISTS (SELECT 1 FROM profiles WHERE id = '15e512c6-73d4-4d0b-9696-447fec288482') THEN 'HAS PROFILE' ELSE 'NO PROFILE' END as status
UNION ALL
SELECT
    'Member 2 (michelebekker007@gmail.com)' as member_check,
    CASE WHEN EXISTS (SELECT 1 FROM profiles WHERE id = '93c56842-f706-4339-a5f2-fb078d18255f') THEN 'HAS PROFILE' ELSE 'NO PROFILE' END as status;

-- If they don't have profiles, create them
INSERT INTO profiles (id, email, role, created_at, updated_at)
VALUES (
    '15e512c6-73d4-4d0b-9696-447fec288482',
    'houselillian5@gmail.com',
    'member',
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

INSERT INTO profiles (id, email, role, created_at, updated_at)
VALUES (
    '93c56842-f706-4339-a5f2-fb078d18255f',
    'michelebekker007@gmail.com',
    'trusted_partner',
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- Verify profiles were created
SELECT '=== PROFILES AFTER CREATION ===' as info;
SELECT id, email, role FROM profiles
WHERE id IN ('15e512c6-73d4-4d0b-9696-447fec288482', '93c56842-f706-4339-a5f2-fb078d18255f');