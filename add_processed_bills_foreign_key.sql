-- Add missing foreign key from processed_bills.member_id to profiles.id
-- This allows joins between bill approvals and member profiles
-- Note: The table uses 'member_id' column, but the service expects 'user_id' in the FK name

ALTER TABLE processed_bills 
DROP CONSTRAINT IF EXISTS processed_bills_member_id_fkey;

ALTER TABLE processed_bills
ADD CONSTRAINT processed_bills_member_id_fkey 
FOREIGN KEY (member_id) 
REFERENCES profiles(id) 
ON DELETE CASCADE;

-- ALSO add an alias foreign key with the name the service expects
-- This is needed because bill_approval_service.dart references processed_bills_user_id_fkey
ALTER TABLE processed_bills 
DROP CONSTRAINT IF EXISTS processed_bills_user_id_fkey;

-- Note: We can't create a second FK on the same column with a different name
-- Instead, we need to fix the service to use the correct FK name

-- Verify the foreign key was created
SELECT
  tc.constraint_name,
  tc.table_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
  JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
  JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY' 
  AND tc.table_name = 'processed_bills'
  AND kcu.column_name = 'member_id';
