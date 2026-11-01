-- ============================================================================
-- DEACTIVATION FEATURE VERIFICATION & MONITORING SCRIPT
-- Date: 2026-01-09
-- Purpose: Verify TP and Member deactivation works correctly
-- ============================================================================

-- =============================================================================
-- PART 1: VERIFY SCHEMA IS PROPERLY SET UP
-- =============================================================================

-- Check deactivation columns exist in profiles
SELECT 
    column_name, 
    data_type, 
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'profiles' 
AND column_name IN ('is_deactivated', 'deactivation_reason', 'deactivated_at')
ORDER BY column_name;

-- Check deactivation columns in trusted_partners
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns
WHERE table_name = 'trusted_partners' 
AND column_name = 'is_deactivated';

-- Check all required indexes exist
SELECT 
    indexname, 
    tablename,
    indexdef
FROM pg_indexes 
WHERE (tablename = 'profiles' OR tablename = 'trusted_partners' OR tablename = 'subscriptions')
AND (indexname LIKE '%deactivat%' OR indexname LIKE '%status%')
ORDER BY tablename, indexname;

-- =============================================================================
-- PART 2: VERIFY RLS POLICIES ARE IN PLACE
-- =============================================================================

-- Check RLS is enabled on profiles table
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'profiles';

-- Check all deactivation-related RLS policies
SELECT 
    tablename,
    policyname,
    cmd,
    qual
FROM pg_policies
WHERE tablename IN ('profiles', 'trusted_partner_discounts')
AND policyname LIKE '%deactivat%' OR policyname LIKE '%active%'
ORDER BY tablename, policyname;

-- =============================================================================
-- PART 3: VERIFY TRUSTED PARTNER DEACTIVATION
-- =============================================================================

-- Get all trusted partners with deactivation status
SELECT 
    p.id,
    p.name,
    p.surname,
    p.email,
    p.role,
    p.is_deactivated,
    p.deactivation_reason,
    p.deactivated_at,
    tp.is_deactivated as tp_is_deactivated,
    tp.business_name,
    COUNT(tpd.id) as active_deals_count
FROM profiles p
LEFT JOIN trusted_partners tp ON p.id = tp.user_id
LEFT JOIN trusted_partner_discounts tpd ON tp.user_id = tpd.trusted_partner_id AND tpd.is_active = TRUE
WHERE p.role = 'trusted_partner'
GROUP BY p.id, tp.user_id, tp.is_deactivated, tp.business_name
ORDER BY p.created_at DESC
LIMIT 20;

-- Check if any TP's deals are still visible to members after deactivation
SELECT 
    p.id as tp_id,
    p.name,
    p.is_deactivated,
    COUNT(tpd.id) as total_deals,
    COUNT(CASE WHEN tpd.is_active = TRUE THEN 1 END) as active_deals,
    COUNT(CASE WHEN tpd.is_active = FALSE THEN 1 END) as inactive_deals
FROM profiles p
LEFT JOIN trusted_partner_discounts tpd ON p.id = tpd.trusted_partner_id
WHERE p.role = 'trusted_partner' AND p.is_deactivated = TRUE
GROUP BY p.id, p.name, p.is_deactivated;

-- Verify deactivated TP's discounts are marked inactive
SELECT 
    tp.user_id,
    tp.business_name,
    COUNT(tpd.id) as total_discounts,
    COUNT(CASE WHEN tpd.is_active = FALSE THEN 1 END) as inactive_discounts,
    CASE 
        WHEN COUNT(CASE WHEN tpd.is_active = TRUE THEN 1 END) = 0 THEN 'PASS: All discounts inactive'
        ELSE 'FAIL: Some discounts still active'
    END as deactivation_check
FROM trusted_partners tp
LEFT JOIN trusted_partner_discounts tpd ON tp.user_id = tpd.trusted_partner_id
WHERE tp.is_deactivated = TRUE
GROUP BY tp.user_id, tp.business_name;

-- =============================================================================
-- PART 4: VERIFY MEMBER DEACTIVATION
-- =============================================================================

-- Get all members with deactivation status
SELECT 
    p.id,
    p.name,
    p.surname,
    p.email,
    p.role,
    p.is_deactivated,
    p.deactivation_reason,
    p.deactivated_at,
    s.status as subscription_status,
    s.paystack_subscription_code,
    COUNT(uqc.id) as total_qr_codes,
    COUNT(CASE WHEN uqc.is_active = TRUE THEN 1 END) as active_qr_codes
FROM profiles p
LEFT JOIN subscriptions s ON p.id = s.user_id
LEFT JOIN user_qr_codes uqc ON p.id = uqc.user_id
WHERE p.role = 'member'
GROUP BY p.id, s.id
ORDER BY p.created_at DESC
LIMIT 20;

-- Check deactivated members' subscription status
SELECT 
    p.id as member_id,
    p.name,
    p.email,
    p.is_deactivated,
    s.status as subscription_status,
    s.paystack_subscription_code,
    p.paystack_customer_code,
    CASE 
        WHEN s.status = 'deactivated' THEN 'PASS: Subscription marked deactivated'
        ELSE 'FAIL: Subscription not deactivated'
    END as subscription_check
FROM profiles p
LEFT JOIN subscriptions s ON p.id = s.user_id
WHERE p.role = 'member' AND p.is_deactivated = TRUE;

-- Verify deactivated member's QR codes are disabled
SELECT 
    p.id as member_id,
    p.name,
    p.is_deactivated,
    COUNT(uqc.id) as total_qr_codes,
    COUNT(CASE WHEN uqc.is_active = FALSE THEN 1 END) as inactive_qr_codes,
    CASE 
        WHEN COUNT(CASE WHEN uqc.is_active = TRUE THEN 1 END) = 0 THEN 'PASS: All QR codes inactive'
        ELSE 'FAIL: Some QR codes still active'
    END as qr_deactivation_check
FROM profiles p
LEFT JOIN user_qr_codes uqc ON p.id = uqc.user_id
WHERE p.role = 'member' AND p.is_deactivated = TRUE
GROUP BY p.id, p.name, p.is_deactivated;

-- =============================================================================
-- PART 5: VERIFY PAYSTACK INTEGRATION
-- =============================================================================

-- Check Paystack subscription codes for deactivated members
SELECT 
    p.id,
    p.name,
    p.email,
    p.is_deactivated,
    s.paystack_subscription_code,
    p.paystack_customer_code,
    s.status,
    CASE 
        WHEN s.paystack_subscription_code IS NOT NULL THEN 'Has Paystack subscription'
        ELSE 'No Paystack subscription'
    END as paystack_status
FROM profiles p
LEFT JOIN subscriptions s ON p.id = s.user_id
WHERE p.role = 'member' AND p.is_deactivated = TRUE
AND s.paystack_subscription_code IS NOT NULL;

-- Check all Paystack codes for monitoring
SELECT 
    p.id,
    p.name,
    p.is_deactivated,
    COUNT(s.id) as subscription_count,
    STRING_AGG(s.paystack_subscription_code, ', ') as paystack_codes,
    STRING_AGG(s.status, ', ') as statuses
FROM profiles p
LEFT JOIN subscriptions s ON p.id = s.user_id
WHERE p.role = 'member'
GROUP BY p.id, p.name, p.is_deactivated
HAVING COUNT(s.id) > 0
ORDER BY p.is_deactivated DESC, p.created_at DESC
LIMIT 30;

-- =============================================================================
-- PART 6: VERIFY APP TRACKING & VISIBILITY
-- =============================================================================

-- Test: Members should NOT see deactivated TPs' deals (RLS test)
-- This shows what a member would see (simulated by removing deactivated TPs)
SELECT 
    tpd.id as deal_id,
    tpd.name as deal_name,
    tp.business_name,
    tp.user_id as tp_id,
    p.is_deactivated as tp_is_deactivated,
    tpd.is_active,
    CASE 
        WHEN p.is_deactivated = FALSE AND tpd.is_active = TRUE THEN 'VISIBLE'
        WHEN p.is_deactivated = TRUE THEN 'HIDDEN (TP deactivated)'
        WHEN tpd.is_active = FALSE THEN 'HIDDEN (deal inactive)'
    END as member_visibility
FROM trusted_partner_discounts tpd
JOIN trusted_partners tp ON tpd.trusted_partner_id = tp.user_id
JOIN profiles p ON tp.user_id = p.id
WHERE p.role = 'trusted_partner'
ORDER BY p.is_deactivated DESC, tpd.created_at DESC
LIMIT 20;

-- Check for any orphaned data (deactivated accounts with active records)
SELECT 
    'Deactivated TP with active deals' as issue_type,
    COUNT(*) as count
FROM trusted_partner_discounts tpd
JOIN trusted_partners tp ON tpd.trusted_partner_id = tp.user_id
WHERE tp.is_deactivated = TRUE AND tpd.is_active = TRUE

UNION ALL

SELECT 
    'Deactivated member with active QR codes',
    COUNT(*)
FROM user_qr_codes uqc
JOIN profiles p ON uqc.user_id = p.id
WHERE p.is_deactivated = TRUE AND uqc.is_active = TRUE

UNION ALL

SELECT 
    'Deactivated member with active subscription',
    COUNT(*)
FROM subscriptions s
JOIN profiles p ON s.user_id = p.id
WHERE p.is_deactivated = TRUE AND s.status != 'deactivated';

-- =============================================================================
-- PART 7: AUDIT TRAIL & MONITORING
-- =============================================================================

-- Show all deactivations with timestamps
SELECT 
    id,
    name,
    surname,
    email,
    role,
    is_deactivated,
    deactivated_at,
    deactivation_reason,
    (NOW() - deactivated_at)::text as time_since_deactivation
FROM profiles
WHERE is_deactivated = TRUE
ORDER BY deactivated_at DESC;

-- Count deactivations by role and date
SELECT 
    role,
    DATE(deactivated_at) as deactivation_date,
    COUNT(*) as count
FROM profiles
WHERE is_deactivated = TRUE AND deactivated_at IS NOT NULL
GROUP BY role, DATE(deactivated_at)
ORDER BY deactivation_date DESC;

-- Most common deactivation reasons
SELECT 
    deactivation_reason,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM profiles WHERE is_deactivated = TRUE), 2) as percentage
FROM profiles
WHERE is_deactivated = TRUE AND deactivation_reason IS NOT NULL
GROUP BY deactivation_reason
ORDER BY count DESC;

-- =============================================================================
-- PART 8: DETAILED DEACTIVATION REPORT
-- =============================================================================

-- Comprehensive deactivation report
SELECT 
    'TRUSTED PARTNERS' as account_type,
    COUNT(*) as total_count,
    COUNT(CASE WHEN is_deactivated = TRUE THEN 1 END) as deactivated_count,
    ROUND(COUNT(CASE WHEN is_deactivated = TRUE THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as deactivation_percentage
FROM profiles
WHERE role = 'trusted_partner'

UNION ALL

SELECT 
    'MEMBERS',
    COUNT(*),
    COUNT(CASE WHEN is_deactivated = TRUE THEN 1 END),
    ROUND(COUNT(CASE WHEN is_deactivated = TRUE THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2)
FROM profiles
WHERE role = 'member';

-- =============================================================================
-- PART 9: TESTING QUERIES - RUN THESE TO TEST FUNCTIONALITY
-- =============================================================================

-- Find a test TP to deactivate (change ID to real ID)
-- SELECT id, name, surname, email FROM profiles WHERE role = 'trusted_partner' LIMIT 1;

-- Find a test member to deactivate (change ID to real ID)
-- SELECT id, name, surname, email FROM profiles WHERE role = 'member' LIMIT 1;

-- After deactivation, verify with these:
-- SELECT * FROM profiles WHERE id = '[TP_USER_ID]' AND role = 'trusted_partner';
-- SELECT is_active, COUNT(*) FROM trusted_partner_discounts WHERE trusted_partner_id = '[TP_USER_ID]' GROUP BY is_active;

-- For members:
-- SELECT * FROM profiles WHERE id = '[MEMBER_USER_ID]' AND role = 'member';
-- SELECT status FROM subscriptions WHERE user_id = '[MEMBER_USER_ID]';
-- SELECT is_active, COUNT(*) FROM user_qr_codes WHERE user_id = '[MEMBER_USER_ID]' GROUP BY is_active;

-- =============================================================================
-- VERIFICATION COMPLETE
-- Check results above for any FAIL items
-- =============================================================================
