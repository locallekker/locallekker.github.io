-- Diagnostic queries to verify admin deal creation permissions
-- Run these to check if the admin and business are properly configured

-- 1. Check if the current user is an admin
SELECT 
    user_id,
    role,
    'Current user is admin: ' || CASE WHEN role = 'admin' THEN 'YES' ELSE 'NO' END as status
FROM public.memberships
WHERE user_id = auth.uid();

-- 2. Check which businesses allow admin deal creation
SELECT
    b.id as business_id,
    b.name as business_name,
    b.owner_member_id,
    p.name || ' ' || p.surname as owner_name,
    b.allow_admin_deal_creation,
    CASE
        WHEN b.allow_admin_deal_creation = true THEN 'Admin can create deals'
        ELSE 'Admin CANNOT create deals'
    END as permission_status
FROM public.businesses b
LEFT JOIN public.profiles p ON p.id = b.owner_member_id
ORDER BY b.name;

-- 3. Check if a specific trusted partner has allowed admin deal creation
-- Replace 'PARTNER_UUID_HERE' with the actual partner's user ID
SELECT
    b.id as business_id,
    b.name as business_name,
    b.owner_member_id as partner_user_id,
    p.name || ' ' || p.surname as partner_name,
    b.allow_admin_deal_creation,
    EXISTS (
        SELECT 1 FROM public.memberships m
        WHERE m.user_id = auth.uid() AND m.role = 'admin'
    ) as current_user_is_admin,
    CASE
        WHEN b.allow_admin_deal_creation = true AND EXISTS (
            SELECT 1 FROM public.memberships m
            WHERE m.user_id = auth.uid() AND m.role = 'admin'
        ) THEN 'UPLOAD SHOULD WORK'
        WHEN b.allow_admin_deal_creation = false THEN 'Partner has NOT allowed admin deal creation'
        WHEN NOT EXISTS (
            SELECT 1 FROM public.memberships m
            WHERE m.user_id = auth.uid() AND m.role = 'admin'
        ) THEN 'Current user is NOT an admin'
        ELSE 'UNKNOWN ISSUE'
    END as diagnosis
FROM public.businesses b
LEFT JOIN public.profiles p ON p.id = b.owner_member_id
WHERE b.owner_member_id = 'PARTNER_UUID_HERE';

-- 4. Test the path parsing for a sample upload path
-- Replace 'partner-uuid-here' with actual partner UUID
SELECT 
    'deal_images/partner-uuid-here/test.jpg' as sample_path,
    split_part('deal_images/partner-uuid-here/test.jpg', '/', 1) as segment_1,
    split_part('deal_images/partner-uuid-here/test.jpg', '/', 2) as segment_2_partner_id,
    split_part('deal_images/partner-uuid-here/test.jpg', '/', 3) as segment_3_filename;
