
-- Better verification: Check for any recent trusted partner creation (last 1 hour)
-- This doesn't depend on email pattern

SELECT 
    CASE 
        WHEN COUNT(*) = 4 THEN '✅ SUCCESS: Recent trusted partner creation works!'
        WHEN COUNT(*) > 0 THEN '⚠️ PARTIAL: Some records missing - check details below'
        ELSE '❌ FAILED: No recent trusted partner records found'
    END as status,
    COUNT(*) as checks_passed
FROM (
    -- Check 1: Recent user in auth.users with trusted_partner type
    SELECT 1 as check_id WHERE EXISTS (
        SELECT 1 FROM auth.users 
        WHERE created_at > NOW() - INTERVAL '1 hour'
        AND raw_user_meta_data->>'user_type' = 'trusted_partner'
    )
    
    UNION ALL
    
    -- Check 2: Recent profile with trusted_partner role and admin flags
    SELECT 2 WHERE EXISTS (
        SELECT 1 FROM profiles 
        WHERE created_at > NOW() - INTERVAL '1 hour'
        AND role = 'trusted_partner'
        AND admin_created = true
        AND password_set = false
    )
    
    UNION ALL
    
    -- Check 3: Recent membership with trusted_partner role
    SELECT 3 WHERE EXISTS (
        SELECT 1 FROM memberships 
        WHERE created_at > NOW() - INTERVAL '1 hour'
        AND role = 'trusted_partner'
    )
    
    UNION ALL
    
    -- Check 4: Recent trusted partner record
    SELECT 4 WHERE EXISTS (
        SELECT 1 FROM trusted_partners 
        WHERE created_at > NOW() - INTERVAL '1 hour'
        AND business_name IS NOT NULL
    )
) checks;

-- Show details of recent trusted partner creation
SELECT 
    'Recent Trusted Partner Details:' as info,
    au.email as auth_email,
    au.raw_user_meta_data->>'user_type' as user_type,
    au.raw_user_meta_data->>'admin_created' as admin_created,
    p.name,
    p.surname,
    p.role,
    p.admin_created as profile_admin_created,
    p.password_set,
    m.role as membership_role,
    tp.business_name,
    au.created_at as auth_created,
    p.created_at as profile_created,
    m.created_at as membership_created,
    tp.created_at as tp_created
FROM auth.users au
JOIN profiles p ON au.id = p.id
LEFT JOIN memberships m ON au.id = m.user_id
LEFT JOIN trusted_partners tp ON au.id = tp.user_id
WHERE au.created_at > NOW() - INTERVAL '1 hour'
AND au.raw_user_meta_data->>'user_type' = 'trusted_partner'
ORDER BY au.created_at DESC;

