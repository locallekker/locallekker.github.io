-- Diagnostic: Check for remaining traces of deleted Trusted Partner
-- UID: 1916d77f-596f-4e9f-825f-dedf7a11bbf8

-- ============================================================================
-- Check all tables for references to this UID
-- ============================================================================

-- 1. Check profiles table (should be deleted)
SELECT 'profiles' as table_name, COUNT(*) as remaining_rows
FROM profiles
WHERE id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- 2. Check memberships table (should be deleted)
SELECT 'memberships' as table_name, COUNT(*) as remaining_rows
FROM memberships
WHERE user_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- 3. Check businesses table (should be deleted)
SELECT 'businesses' as table_name, COUNT(*) as remaining_rows
FROM businesses
WHERE owner_member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- 4. Check trusted_partner_discounts (check if business still has discounts)
SELECT 'trusted_partner_discounts' as table_name, COUNT(*) as remaining_rows
FROM trusted_partner_discounts
WHERE business_id IN (
    SELECT id FROM businesses WHERE owner_member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
);

-- 5. Check deal_authorizations (should be deleted via cascade)
SELECT 'deal_authorizations' as table_name, COUNT(*) as remaining_rows
FROM deal_authorizations
WHERE discount_id IN (
    SELECT id FROM trusted_partner_discounts 
    WHERE business_id IN (
        SELECT id FROM businesses WHERE owner_member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
    )
);

-- 6. Check processed_bills (should be deleted)
SELECT 'processed_bills' as table_name, COUNT(*) as remaining_rows
FROM processed_bills
WHERE business_id IN (
    SELECT id FROM businesses WHERE owner_member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
)
OR member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
OR partner_id IN (
    SELECT id FROM businesses WHERE owner_member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
);

-- 7. Check subscriptions (should be deleted)
SELECT 'subscriptions' as table_name, COUNT(*) as remaining_rows
FROM subscriptions
WHERE user_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- 8. Check user_qr_codes (should be deleted)
SELECT 'user_qr_codes' as table_name, COUNT(*) as remaining_rows
FROM user_qr_codes
WHERE user_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- 9. Check notifications (should be deleted)
SELECT 'notifications' as table_name, COUNT(*) as remaining_rows
FROM notifications
WHERE user_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- 10. Check archived_receipts (should have data)
SELECT 'archived_receipts' as table_name, COUNT(*) as archived_rows
FROM archived_receipts
WHERE trusted_partner_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- 11. Check archived_paystack_data (should have data)
SELECT 'archived_paystack_data' as table_name, COUNT(*) as archived_rows
FROM archived_paystack_data
WHERE trusted_partner_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- 12. Check archived_pending_payments (should have data if any payments existed)
SELECT 'archived_pending_payments' as table_name, COUNT(*) as archived_rows
FROM archived_pending_payments
WHERE trusted_partner_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- ============================================================================
-- Summary: Show any remaining business data
-- ============================================================================
SELECT 'Remaining business data:' as info;

SELECT 
    b.id,
    b.name,
    b.owner_member_id,
    COUNT(DISTINCT tpd.id) as discount_count,
    COUNT(DISTINCT pb.id) as bill_count
FROM businesses b
LEFT JOIN trusted_partner_discounts tpd ON tpd.business_id = b.id
LEFT JOIN processed_bills pb ON pb.business_id = b.id
WHERE b.owner_member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
GROUP BY b.id, b.name, b.owner_member_id;

-- ============================================================================
-- NOTE: auth.users deletion
-- ============================================================================
-- The admin_delete_trusted_partner function does NOT delete from auth.users
-- This must be done separately via Supabase Auth Admin API or Dashboard:
-- 1. Go to Supabase Dashboard > Authentication > Users
-- 2. Find user 1916d77f-596f-4e9f-825f-dedf7a11bbf8
-- 3. Click "Delete user" button
-- 
-- This separation is intentional - auth.users is managed by Supabase Auth service
-- The function cleans up all application data in public schema
