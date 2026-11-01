-- =============================================================================
-- FIX REMAINING FOREIGN KEY CONSTRAINTS
-- =============================================================================
-- This script fixes the two foreign keys that still use NO ACTION,
-- which could block trusted partner deletions.
-- =============================================================================

-- =============================================================================
-- 1. FIX MEMBER_RECEIPTS TABLE
-- =============================================================================
-- Change member_receipts.member_id from NO ACTION to CASCADE
-- This ensures member receipts are deleted when the member profile is deleted

ALTER TABLE public.member_receipts 
DROP CONSTRAINT IF EXISTS member_receipts_member_id_fkey;

ALTER TABLE public.member_receipts 
ADD CONSTRAINT member_receipts_member_id_fkey 
FOREIGN KEY (member_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- =============================================================================
-- 2. FIX PROCESSED_BILLS.DISCOUNT_ID
-- =============================================================================
-- Change processed_bills.discount_id from NO ACTION to SET NULL
-- This preserves bill history but removes the discount reference when deleted

ALTER TABLE public.processed_bills 
DROP CONSTRAINT IF EXISTS processed_bills_discount_id_fkey;

ALTER TABLE public.processed_bills 
ADD CONSTRAINT processed_bills_discount_id_fkey 
FOREIGN KEY (discount_id) REFERENCES public.trusted_partner_discounts(id) ON DELETE SET NULL;

-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Check that the constraints are now properly set

SELECT 
    tc.table_name, 
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name,
    rc.delete_rule
FROM 
    information_schema.table_constraints AS tc 
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
      AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage AS ccu
      ON ccu.constraint_name = tc.constraint_name
      AND ccu.table_schema = tc.table_schema
    JOIN information_schema.referential_constraints AS rc
      ON rc.constraint_name = tc.constraint_name
      AND rc.constraint_schema = tc.table_schema
WHERE 
    tc.constraint_type = 'FOREIGN KEY' 
    AND tc.table_schema = 'public'
    AND (
        (tc.table_name = 'member_receipts' AND kcu.column_name = 'member_id')
        OR (tc.table_name = 'processed_bills' AND kcu.column_name = 'discount_id')
    )
ORDER BY 
    tc.table_name, kcu.column_name;

-- Expected results:
-- member_receipts | member_id | profiles | id | CASCADE
-- processed_bills | discount_id | trusted_partner_discounts | id | SET NULL
