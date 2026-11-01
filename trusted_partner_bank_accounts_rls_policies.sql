-- ========================================
-- RLS POLICIES FOR TRUSTED_PARTNER_BANK_ACCOUNTS
-- Updated to use user_id instead of business_id
-- ========================================

-- Drop old policies if they exist
DROP POLICY IF EXISTS "Users can view own bank accounts" ON trusted_partner_bank_accounts;
DROP POLICY IF EXISTS "Users can insert own bank accounts" ON trusted_partner_bank_accounts;
DROP POLICY IF EXISTS "Users can update own bank accounts" ON trusted_partner_bank_accounts;
DROP POLICY IF EXISTS "Users can delete own bank accounts" ON trusted_partner_bank_accounts;

-- Enable RLS
ALTER TABLE trusted_partner_bank_accounts ENABLE ROW LEVEL SECURITY;

-- Policy: Trusted partners can view their own bank accounts
CREATE POLICY "Users can view own bank accounts"
ON trusted_partner_bank_accounts
FOR SELECT
USING (auth.uid() = user_id);

-- Policy: Trusted partners can insert their own bank accounts
CREATE POLICY "Users can insert own bank accounts"
ON trusted_partner_bank_accounts
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Policy: Trusted partners can update their own bank accounts
CREATE POLICY "Users can update own bank accounts"
ON trusted_partner_bank_accounts
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Policy: Trusted partners can delete/deactivate their own bank accounts
CREATE POLICY "Users can delete own bank accounts"
ON trusted_partner_bank_accounts
FOR DELETE
USING (auth.uid() = user_id);

-- Optional: Admin access policies
-- Uncomment if you want admins to have full access

-- CREATE POLICY "Admins can view all bank accounts"
-- ON trusted_partner_bank_accounts
-- FOR SELECT
-- USING (
--   EXISTS (
--     SELECT 1 FROM profiles 
--     WHERE profiles.id = auth.uid() 
--     AND profiles.role = 'admin'
--   )
-- );

-- CREATE POLICY "Admins can update all bank accounts"
-- ON trusted_partner_bank_accounts
-- FOR UPDATE
-- USING (
--   EXISTS (
--     SELECT 1 FROM profiles 
--     WHERE profiles.id = auth.uid() 
--     AND profiles.role = 'admin'
--   )
-- );

-- Verify policies
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM 
    pg_policies
WHERE 
    tablename = 'trusted_partner_bank_accounts'
ORDER BY 
    policyname;
