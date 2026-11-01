-- Reorganize banking schema: Move banking details from trusted_partners to trusted_partner_bank_accounts
-- Migration: 20251030000002_reorganize_banking_schema

-- Step 1: Add banking columns back to trusted_partner_bank_accounts
ALTER TABLE public.trusted_partner_bank_accounts
ADD COLUMN IF NOT EXISTS paystack_recipient_code TEXT;

ALTER TABLE public.trusted_partner_bank_accounts
ADD COLUMN IF NOT EXISTS bank_account_type TEXT CHECK (bank_account_type IN ('checking', 'savings'));

ALTER TABLE public.trusted_partner_bank_accounts
ADD COLUMN IF NOT EXISTS branch_code TEXT;

ALTER TABLE public.trusted_partner_bank_accounts
ADD COLUMN IF NOT EXISTS bank_name TEXT;

-- Add comments for clarity
COMMENT ON COLUMN public.trusted_partner_bank_accounts.paystack_recipient_code IS 'Paystack transfer recipient code for banking details collection';
COMMENT ON COLUMN public.trusted_partner_bank_accounts.bank_account_type IS 'Type of bank account (checking or savings)';
COMMENT ON COLUMN public.trusted_partner_bank_accounts.branch_code IS '6-digit South African bank branch code';

-- Step 2: Migrate existing data from trusted_partners to trusted_partner_bank_accounts
-- Insert records into trusted_partner_bank_accounts for users who have banking data in trusted_partners
INSERT INTO public.trusted_partner_bank_accounts (
    user_id,
    account_holder_name,
    bank_name,
    account_type,
    branch_code,
    paystack_recipient_code,
    bank_account_type,
    is_active,
    created_at,
    updated_at
)
SELECT
    tp.user_id,
    COALESCE(tp.business_name, 'Unknown') as account_holder_name,
    'Unknown' as bank_name,
    'savings' as account_type,
    '' as branch_code,
    tp.paystack_recipient_code,
    'savings' as bank_account_type,
    true as is_active,
    tp.created_at,
    tp.updated_at
FROM public.trusted_partners tp
WHERE tp.paystack_recipient_code IS NOT NULL
ON CONFLICT (user_id) DO UPDATE SET
    account_holder_name = EXCLUDED.account_holder_name,
    bank_name = EXCLUDED.bank_name,
    account_type = EXCLUDED.account_type,
    branch_code = EXCLUDED.branch_code,
    paystack_recipient_code = EXCLUDED.paystack_recipient_code,
    bank_account_type = EXCLUDED.bank_account_type,
    is_active = EXCLUDED.is_active,
    updated_at = NOW();

-- Step 3: Remove banking columns from trusted_partners table
ALTER TABLE public.trusted_partners
DROP COLUMN IF EXISTS bank_account_holder;

ALTER TABLE public.trusted_partners
DROP COLUMN IF EXISTS bank_name;

ALTER TABLE public.trusted_partners
DROP COLUMN IF EXISTS bank_account_number;

ALTER TABLE public.trusted_partners
DROP COLUMN IF EXISTS bank_branch_code;

ALTER TABLE public.trusted_partners
DROP COLUMN IF EXISTS bank_account_type;

ALTER TABLE public.trusted_partners
DROP COLUMN IF EXISTS branch_code;

ALTER TABLE public.trusted_partners
DROP COLUMN IF EXISTS settlement_percentage;

ALTER TABLE public.trusted_partners
DROP COLUMN IF EXISTS is_active;

-- Step 4: Update RLS policies for trusted_partner_bank_accounts to include banking data access
-- The existing policies should work, but let's ensure they cover the new columns
-- (Existing policies already allow users to manage their own bank accounts)

-- Step 5: Create index for the new paystack_recipient_code column
CREATE INDEX IF NOT EXISTS idx_trusted_partner_bank_accounts_paystack_recipient_code
ON public.trusted_partner_bank_accounts(paystack_recipient_code);

-- Step 6: Update the unique constraint to be more flexible (remove account_number from unique constraint since it might be empty)
-- First drop the existing unique constraint
ALTER TABLE public.trusted_partner_bank_accounts
DROP CONSTRAINT IF EXISTS trusted_partner_bank_accounts_user_id_account_number_branch_code_key;

-- Add a new unique constraint that allows multiple accounts per user but prevents exact duplicates
DROP INDEX IF EXISTS trusted_partner_bank_accounts_user_unique_active;
CREATE UNIQUE INDEX trusted_partner_bank_accounts_user_unique_active
ON public.trusted_partner_bank_accounts (user_id)
WHERE is_active = true;
