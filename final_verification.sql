
-- Verification for the actual trusted partner created: thecraftsmanel@gmail.com
SELECT
    check_id,
    CASE
        WHEN check_id = 1 THEN 'User exists in auth.users'
        WHEN check_id = 2 THEN 'Profile record exists with correct flags'
        WHEN check_id = 3 THEN 'Membership record exists'
        WHEN check_id = 4 THEN 'Trusted partner record exists'
    END as check_description,
    CASE WHEN check_result THEN '✅ PASS' ELSE '❌ FAIL' END as status
FROM (
    -- Check 1: User exists in auth.users
    SELECT 1 as check_id,
           EXISTS (
               SELECT 1 FROM auth.users
               WHERE email = 'thecraftsmanel@gmail.com'
               AND raw_user_meta_data->>'user_type' = 'trusted_partner'
           ) as check_result

    UNION ALL

    -- Check 2: Profile record exists with correct flags
    SELECT 2 as check_id,
           EXISTS (
               SELECT 1 FROM profiles
               WHERE email = 'thecraftsmanel@gmail.com'
               AND role = 'trusted_partner'
               AND admin_created = true
               AND password_set = false
           ) as check_result

    UNION ALL

    -- Check 3: Membership record exists
    SELECT 3 as check_id,
           EXISTS (
               SELECT 1 FROM memberships m
               JOIN profiles p ON m.user_id = p.id
               WHERE p.email = 'thecraftsmanel@gmail.com'
               AND m.role = 'trusted_partner'
           ) as check_result

    UNION ALL

    -- Check 4: Trusted partner record exists
    SELECT 4 as check_id,
           EXISTS (
               SELECT 1 FROM trusted_partners tp
               JOIN profiles p ON tp.user_id = p.id
               WHERE p.email = 'thecraftsmanel@gmail.com'
               AND tp.business_name IS NOT NULL
           ) as check_result
) checks
ORDER BY check_id;

-- Summary for thecraftsmanel@gmail.com
SELECT
    COUNT(*) as total_checks,
    SUM(CASE WHEN check_result THEN 1 ELSE 0 END) as passed_checks,
    CASE
        WHEN COUNT(*) = SUM(CASE WHEN check_result THEN 1 ELSE 0 END) THEN '✅ SUCCESS: All records created correctly for thecraftsmanel@gmail.com'
        ELSE '❌ FAILED: Missing records for thecraftsmanel@gmail.com'
    END as overall_status
FROM (
    -- Check 1: User exists in auth.users
    SELECT EXISTS (
        SELECT 1 FROM auth.users
        WHERE email = 'thecraftsmanel@gmail.com'
        AND raw_user_meta_data->>'user_type' = 'trusted_partner'
    ) as check_result

    UNION ALL

    -- Check 2: Profile record exists with correct flags
    SELECT EXISTS (
        SELECT 1 FROM profiles
        WHERE email = 'thecraftsmanel@gmail.com'
        AND role = 'trusted_partner'
        AND admin_created = true
        AND password_set = false
    ) as check_result

    UNION ALL

    -- Check 3: Membership record exists
    SELECT EXISTS (
        SELECT 1 FROM memberships m
        JOIN profiles p ON m.user_id = p.id
        WHERE p.email = 'thecraftsmanel@gmail.com'
        AND m.role = 'trusted_partner'
    ) as check_result

    UNION ALL

    -- Check 4: Trusted partner record exists
    SELECT EXISTS (
        SELECT 1 FROM trusted_partners tp
        JOIN profiles p ON tp.user_id = p.id
        WHERE p.email = 'thecraftsmanel@gmail.com'
        AND tp.business_name IS NOT NULL
    ) as check_result
) checks;

