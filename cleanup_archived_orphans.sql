-- Clean up orphaned archived records blocking auth.users deletion
-- UID: 1916d77f-596f-4e9f-825f-dedf7a11bbf8

-- ============================================================================
-- STEP 1: Check what's referencing the TP in archived tables
-- ============================================================================
SELECT 'Checking archived records...' as status;

SELECT 
    'archived_receipts with archived_by' as table_type,
    COUNT(*) as count
FROM archived_receipts
WHERE archived_by = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

SELECT 
    'archived_paystack_data with archived_by' as table_type,
    COUNT(*) as count
FROM archived_paystack_data
WHERE archived_by = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

SELECT 
    'archived_pending_payments with archived_by' as table_type,
    COUNT(*) as count
FROM archived_pending_payments
WHERE archived_by = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- ============================================================================
-- STEP 2: Delete archived records where this user is archived_by
-- (these are blocking the auth.users deletion due to RLS checks)
-- ============================================================================
DELETE FROM archived_receipts 
WHERE archived_by = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

DELETE FROM archived_paystack_data 
WHERE archived_by = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

DELETE FROM archived_pending_payments 
WHERE archived_by = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- ============================================================================
-- STEP 3: Verify cleanup
-- ============================================================================
SELECT 'Cleanup complete. Verification:' as status;

SELECT 
    'archived_receipts' as table_name,
    COUNT(*) as remaining_rows
FROM archived_receipts
WHERE archived_by = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
UNION ALL
SELECT 'archived_paystack_data', COUNT(*)
FROM archived_paystack_data
WHERE archived_by = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
UNION ALL
SELECT 'archived_pending_payments', COUNT(*)
FROM archived_pending_payments
WHERE archived_by = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- ============================================================================
-- STEP 4: Now try to delete from auth.users
-- ============================================================================
-- After running the above, the auth.users delete should work
-- Try in Supabase Dashboard > Authentication > Users > Delete user
