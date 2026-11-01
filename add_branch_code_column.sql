-- Add branch_code column to trusted_partners table for storing South African branch codes
-- Since Paystack doesn't store branch codes, we need to store them separately

ALTER TABLE trusted_partners
ADD COLUMN IF NOT EXISTS branch_code VARCHAR(6);

-- Add comment to document the column purpose
COMMENT ON COLUMN trusted_partners.branch_code IS '6-digit South African bank branch code, stored separately from Paystack data';

-- Create index for potential queries on branch_code
CREATE INDEX IF NOT EXISTS idx_trusted_partners_branch_code ON trusted_partners(branch_code);

-- Update RLS policies to include branch_code in SELECT operations
-- The existing policies should already cover this since they use SELECT * or specific column lists
-- But let's verify the policies allow access to the new column

-- Check current policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'trusted_partners'
ORDER BY policyname;