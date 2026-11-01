-- Diagnostic: Find what's blocking auth.users deletion
-- UID: 1916d77f-596f-4e9f-825f-dedf7a11bbf8

-- ============================================================================
-- FIRST: Check what columns exist in key tables
-- ============================================================================
SELECT 
    'Columns in chat_conversations:' as info;

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'chat_conversations'
ORDER BY ordinal_position;

SELECT 
    'Columns in archived_receipts:' as info;

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'archived_receipts'
ORDER BY ordinal_position;

-- ============================================================================
-- Check for references in archived tables (known to exist)
-- ============================================================================
SELECT 'Archived table references:' as check_section;

SELECT 
    'archived_receipts.trusted_partner_id' as reference,
    COUNT(*) as count
FROM archived_receipts
WHERE trusted_partner_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
UNION ALL
SELECT 'archived_receipts.member_id', COUNT(*)
FROM archived_receipts
WHERE member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
UNION ALL
SELECT 'archived_receipts.archived_by', COUNT(*)
FROM archived_receipts
WHERE archived_by = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
UNION ALL
SELECT 'archived_paystack_data.trusted_partner_id', COUNT(*)
FROM archived_paystack_data
WHERE trusted_partner_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
UNION ALL
SELECT 'archived_pending_payments.trusted_partner_id', COUNT(*)
FROM archived_pending_payments
WHERE trusted_partner_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
UNION ALL
SELECT 'archived_pending_payments.member_id', COUNT(*)
FROM archived_pending_payments
WHERE member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
ORDER BY count DESC;

-- ============================================================================
-- Check the auth.users table constraints
-- ============================================================================
SELECT 
    'Checking for foreign key constraints' as info;

-- PostgreSQL way to check constraints
SELECT 
    constraint_name,
    table_name,
    column_name
FROM information_schema.constraint_column_usage
WHERE table_schema = 'auth'
ORDER BY table_name, column_name;

-- ============================================================================
-- Check if there's RLS policy preventing deletion
-- ============================================================================
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename IN (
    'chat_conversations', 'chat_messages', 'notifications',
    'archived_receipts', 'archived_paystack_data', 'archived_pending_payments'
)
ORDER BY tablename, policyname;
