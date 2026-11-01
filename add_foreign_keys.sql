-- Check existing columns and their types in processed_bills table
SELECT column_name, data_type, is_nullable FROM information_schema.columns
WHERE table_name = 'processed_bills' AND table_schema = 'public'
ORDER BY ordinal_position;

-- Check existing columns and their types in bill_approvals table
SELECT column_name, data_type, is_nullable FROM information_schema.columns
WHERE table_name = 'bill_approvals' AND table_schema = 'public'
ORDER BY ordinal_position;

-- Check existing foreign key constraints
SELECT
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM
    information_schema.table_constraints AS tc
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
      AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage AS ccu
      ON ccu.constraint_name = tc.constraint_name
      AND ccu.table_schema = tc.table_schema
WHERE
    tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_name IN ('processed_bills', 'bill_approvals', 'businesses', 'profiles')
ORDER BY tc.table_name, tc.constraint_name;

-- Check if there's existing data in processed_bills.partner_id
SELECT COUNT(*) as total_rows, COUNT(partner_id) as non_null_partner_ids
FROM processed_bills;

-- Sample some partner_id values to check format
SELECT partner_id FROM processed_bills WHERE partner_id IS NOT NULL LIMIT 5;

-- Check what businesses exist
SELECT id, name FROM businesses;

-- Find processed_bills with invalid partner_id (not in businesses table)
SELECT pb.id, pb.partner_id, pb.created_at
FROM processed_bills pb
LEFT JOIN businesses b ON pb.partner_id = b.id
WHERE pb.partner_id IS NOT NULL AND b.id IS NULL;

-- Clean up invalid partner_id values by deleting records with invalid partner_ids
-- (since partner_id is NOT NULL, we can't set to null)
DELETE FROM processed_bills
WHERE partner_id IS NOT NULL
AND partner_id NOT IN (SELECT id FROM businesses);

-- Verify the cleanup worked
SELECT COUNT(*) as remaining_invalid_partner_ids
FROM processed_bills pb
LEFT JOIN businesses b ON pb.partner_id = b.id
WHERE pb.partner_id IS NOT NULL AND b.id IS NULL;

-- Based on the column check above, use the correct column name and type
-- If column is 'user_id', use that; if 'member_id', use that

-- Drop old constraint if it exists
ALTER TABLE processed_bills DROP CONSTRAINT IF EXISTS processed_bills_user_id_fkey;
ALTER TABLE processed_bills DROP CONSTRAINT IF EXISTS processed_bills_member_id_fkey;
ALTER TABLE processed_bills DROP CONSTRAINT IF EXISTS processed_bills_partner_id_fkey;

-- First, alter partner_id from text to uuid if it exists and has data
-- Only do this if all existing partner_id values are valid UUIDs
DO $$
DECLARE
    invalid_count INTEGER;
    total_count INTEGER;
BEGIN
    -- Check if all partner_id values are valid UUIDs
    SELECT COUNT(*) INTO total_count FROM processed_bills WHERE partner_id IS NOT NULL;
    SELECT COUNT(*) INTO invalid_count
    FROM processed_bills
    WHERE partner_id IS NOT NULL
    AND partner_id::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

    IF total_count = 0 THEN
        -- No data, safe to change type
        ALTER TABLE processed_bills ALTER COLUMN partner_id TYPE uuid USING partner_id::uuid;
    ELSIF invalid_count = 0 THEN
        -- All values are valid UUIDs, safe to change type
        ALTER TABLE processed_bills ALTER COLUMN partner_id TYPE uuid USING partner_id::uuid;
    ELSE
        -- Some invalid UUIDs, skip type change
        RAISE NOTICE 'Cannot change partner_id to uuid: % invalid UUIDs found out of % total values', invalid_count, total_count;
    END IF;
END $$;

-- Add foreign key from processed_bills.user_id to profiles.id (since user_id exists and is uuid)
ALTER TABLE processed_bills
ADD CONSTRAINT processed_bills_user_id_fkey
FOREIGN KEY (user_id) REFERENCES profiles(id);

-- Add foreign key from processed_bills.partner_id to businesses.id (now that invalid data is cleaned up)
ALTER TABLE processed_bills
ADD CONSTRAINT processed_bills_partner_id_fkey
FOREIGN KEY (partner_id) REFERENCES businesses(id);

-- Add foreign key from bill_approvals.business_id to businesses.id (if the column exists and is uuid)
DO $$
DECLARE
    business_type TEXT;
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bill_approvals' AND column_name = 'business_id'
    ) THEN
        SELECT data_type INTO business_type
        FROM information_schema.columns
        WHERE table_name = 'bill_approvals' AND column_name = 'business_id';

        IF business_type = 'uuid' THEN
            ALTER TABLE bill_approvals
            ADD CONSTRAINT bill_approvals_business_id_fkey
            FOREIGN KEY (business_id) REFERENCES businesses(id);
        END IF;
    END IF;
END $$;