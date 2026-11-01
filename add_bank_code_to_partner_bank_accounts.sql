-- Add missing columns to trusted_partner_bank_accounts table
-- These columns support Paystack integration for split payments

-- Add bank_code column (Paystack bank code)
ALTER TABLE trusted_partner_bank_accounts 
ADD COLUMN IF NOT EXISTS bank_code TEXT;

-- Add paystack_recipient_code (for transfer recipients)
ALTER TABLE trusted_partner_bank_accounts 
ADD COLUMN IF NOT EXISTS paystack_recipient_code TEXT;

-- Add bank_account_type (duplicate of account_type for consistency)
ALTER TABLE trusted_partner_bank_accounts 
ADD COLUMN IF NOT EXISTS bank_account_type TEXT;

-- Add subaccount_code (Paystack subaccount for split payments)
ALTER TABLE trusted_partner_bank_accounts 
ADD COLUMN IF NOT EXISTS subaccount_code TEXT;

-- Add percentage_charge (split payment percentage)
ALTER TABLE trusted_partner_bank_accounts 
ADD COLUMN IF NOT EXISTS percentage_charge NUMERIC(5,2);

-- Add subaccount_active (whether subaccount is active)
ALTER TABLE trusted_partner_bank_accounts 
ADD COLUMN IF NOT EXISTS subaccount_active BOOLEAN DEFAULT FALSE;

-- Add subaccount_created_at (when subaccount was created)
ALTER TABLE trusted_partner_bank_accounts 
ADD COLUMN IF NOT EXISTS subaccount_created_at TIMESTAMP WITH TIME ZONE;

-- Add comments for documentation
COMMENT ON COLUMN trusted_partner_bank_accounts.bank_code IS 'Paystack bank code for the selected bank (e.g., 632005 for ABSA, 250655 for FNB)';
COMMENT ON COLUMN trusted_partner_bank_accounts.paystack_recipient_code IS 'Paystack transfer recipient code for direct transfers';
COMMENT ON COLUMN trusted_partner_bank_accounts.subaccount_code IS 'Paystack subaccount code for split payments';
COMMENT ON COLUMN trusted_partner_bank_accounts.percentage_charge IS 'Percentage of transaction amount that goes to the partner (e.g., 90.0 for 90%)';
COMMENT ON COLUMN trusted_partner_bank_accounts.subaccount_active IS 'Whether the Paystack subaccount is active and verified';
COMMENT ON COLUMN trusted_partner_bank_accounts.subaccount_created_at IS 'Timestamp when the Paystack subaccount was created';

-- Update existing records to set bank_code based on bank_name if possible
UPDATE trusted_partner_bank_accounts
SET bank_code = CASE
    WHEN LOWER(bank_name) = 'absa bank' THEN '632005'
    WHEN LOWER(bank_name) = 'capitec bank' THEN '470010'
    WHEN LOWER(bank_name) = 'fnb' THEN '250655'
    WHEN LOWER(bank_name) = 'nedbank' THEN '198765'
    WHEN LOWER(bank_name) = 'standard bank' THEN '051001'
    WHEN LOWER(bank_name) = 'investec' THEN '580105'
    WHEN LOWER(bank_name) = 'african bank' THEN '430000'
    WHEN LOWER(bank_name) = 'discovery bank' THEN '679000'
    ELSE NULL
END
WHERE bank_code IS NULL;

-- Sync bank_account_type with account_type for existing records
UPDATE trusted_partner_bank_accounts
SET bank_account_type = account_type
WHERE bank_account_type IS NULL;
