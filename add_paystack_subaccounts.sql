-- Add subaccount support to trusted_partner_bank_accounts table
-- This enables split payments where partners receive funds directly from Paystack

-- Add subaccount_code column to store Paystack subaccount ID
ALTER TABLE trusted_partner_bank_accounts 
ADD COLUMN IF NOT EXISTS subaccount_code TEXT,
ADD COLUMN IF NOT EXISTS percentage_charge NUMERIC(5,2) DEFAULT 90.0,
ADD COLUMN IF NOT EXISTS subaccount_created_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS subaccount_active BOOLEAN DEFAULT true;

-- Add index for faster subaccount lookups
CREATE INDEX IF NOT EXISTS idx_trusted_partner_bank_accounts_subaccount_code 
ON trusted_partner_bank_accounts(subaccount_code);

-- Add comment explaining the percentage_charge column
COMMENT ON COLUMN trusted_partner_bank_accounts.percentage_charge IS 
'Percentage of payment that goes to the partner (e.g., 90.0 means partner gets 90%, platform gets 10%)';

-- Add comment explaining the subaccount_code column
COMMENT ON COLUMN trusted_partner_bank_accounts.subaccount_code IS 
'Paystack subaccount code (e.g., ACCT_xxxxx) for split payments';

-- Update existing records to set default values
-- Set subaccount_active to false for existing records (they need to re-save banking to create subaccount)
UPDATE trusted_partner_bank_accounts 
SET percentage_charge = 90.0, 
    subaccount_active = false
WHERE percentage_charge IS NULL OR subaccount_code IS NULL;

-- Verify the changes
SELECT 
    user_id,
    account_holder_name,
    bank_name,
    paystack_recipient_code,
    subaccount_code,
    percentage_charge,
    subaccount_active,
    created_at,
    subaccount_created_at
FROM trusted_partner_bank_accounts
ORDER BY created_at DESC;
