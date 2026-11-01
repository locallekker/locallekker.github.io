-- Reorganize banking schema: Separate banking details for members and trusted partners
-- Migration: 20251030000002_reorganize_banking_schema

-- Step 1: Create members_bank_accounts table for member banking details
CREATE TABLE IF NOT EXISTS public.members_bank_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    account_holder_name TEXT NOT NULL,
    bank_name TEXT NOT NULL,
    account_number TEXT NOT NULL, -- Masked: only last 4 digits stored (e.g., xxxx1234)
    account_type TEXT CHECK (account_type IN ('checking', 'savings')),
    branch_code TEXT,
    paystack_recipient_code TEXT, -- Paystack transfer recipient code
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Step 2: Create members_card_details table for member credit card details
CREATE TABLE IF NOT EXISTS public.members_card_details (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    authorization_code TEXT NOT NULL, -- Paystack authorization code
    card_type TEXT,
    last4 TEXT NOT NULL, -- Last 4 digits of card (e.g., 1234)
    exp_month INTEGER,
    exp_year INTEGER,
    bank TEXT,
    brand TEXT,
    is_primary BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Step 3: Enable RLS on new tables
ALTER TABLE public.members_bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.members_card_details ENABLE ROW LEVEL SECURITY;

-- Step 4: Create RLS policies for members_bank_accounts
DROP POLICY IF EXISTS "Members can manage their bank accounts" ON public.members_bank_accounts;
CREATE POLICY "Members can manage their bank accounts" ON public.members_bank_accounts
    FOR ALL USING (user_id = auth.uid());

-- Step 5: Create RLS policies for members_card_details
DROP POLICY IF EXISTS "Members can manage their card details" ON public.members_card_details;
CREATE POLICY "Members can manage their card details" ON public.members_card_details
    FOR ALL USING (user_id = auth.uid());

-- Step 6: Add banking columns back to trusted_partner_bank_accounts (skip if already exist)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'trusted_partner_bank_accounts' AND column_name = 'paystack_recipient_code') THEN
        ALTER TABLE public.trusted_partner_bank_accounts ADD COLUMN paystack_recipient_code TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'trusted_partner_bank_accounts' AND column_name = 'bank_account_type') THEN
        ALTER TABLE public.trusted_partner_bank_accounts ADD COLUMN bank_account_type TEXT CHECK (bank_account_type IN ('checking', 'savings'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'trusted_partner_bank_accounts' AND column_name = 'branch_code') THEN
        ALTER TABLE public.trusted_partner_bank_accounts ADD COLUMN branch_code TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'trusted_partner_bank_accounts' AND column_name = 'bank_name') THEN
        ALTER TABLE public.trusted_partner_bank_accounts ADD COLUMN bank_name TEXT;
    END IF;
END $$;

-- Add comments for clarity
COMMENT ON COLUMN public.trusted_partner_bank_accounts.paystack_recipient_code IS 'Paystack transfer recipient code for banking details collection';
COMMENT ON COLUMN public.trusted_partner_bank_accounts.bank_account_type IS 'Type of bank account (checking or savings)';
COMMENT ON COLUMN public.trusted_partner_bank_accounts.branch_code IS '6-digit South African bank branch code';

COMMENT ON COLUMN public.members_bank_accounts.paystack_recipient_code IS 'Paystack transfer recipient code for member banking details';
COMMENT ON COLUMN public.members_bank_accounts.account_number IS 'Masked account number (last 4 digits only, e.g., xxxx1234)';
COMMENT ON COLUMN public.members_card_details.authorization_code IS 'Paystack authorization code for card payments';
COMMENT ON COLUMN public.members_card_details.last4 IS 'Last 4 digits of card number';

-- Step 7: Migrate existing trusted partner data from trusted_partners to trusted_partner_bank_accounts
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

-- Step 8: Migrate existing member banking data (if any exists in profiles or other tables)
-- Note: This assumes any existing member banking data might be in profiles table
-- If members had banking data stored elsewhere, adjust this query accordingly

-- Step 9: Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_members_bank_accounts_user_id
ON public.members_bank_accounts(user_id);

CREATE INDEX IF NOT EXISTS idx_members_bank_accounts_paystack_recipient_code
ON public.members_bank_accounts(paystack_recipient_code);

CREATE INDEX IF NOT EXISTS idx_members_card_details_user_id
ON public.members_card_details(user_id);

CREATE INDEX IF NOT EXISTS idx_members_card_details_authorization_code
ON public.members_card_details(authorization_code);

-- Step 10: Remove banking columns from trusted_partners table (skip if don't exist)
DO $$
BEGIN
    ALTER TABLE public.trusted_partners DROP COLUMN IF EXISTS bank_account_holder;
    ALTER TABLE public.trusted_partners DROP COLUMN IF EXISTS bank_name;
    ALTER TABLE public.trusted_partners DROP COLUMN IF EXISTS bank_account_number;
    ALTER TABLE public.trusted_partners DROP COLUMN IF EXISTS bank_branch_code;
    ALTER TABLE public.trusted_partners DROP COLUMN IF EXISTS bank_account_type;
    ALTER TABLE public.trusted_partners DROP COLUMN IF EXISTS branch_code;
    ALTER TABLE public.trusted_partners DROP COLUMN IF EXISTS settlement_percentage;
    ALTER TABLE public.trusted_partners DROP COLUMN IF EXISTS is_active;
END $$;

-- Step 11: Create unique constraints for data integrity
-- Members can have only one active bank account
DROP INDEX IF EXISTS members_bank_accounts_user_unique_active;
CREATE UNIQUE INDEX members_bank_accounts_user_unique_active
ON public.members_bank_accounts (user_id)
WHERE is_active = true;

-- Members can have only one primary card
DROP INDEX IF EXISTS members_card_details_user_primary;
CREATE UNIQUE INDEX members_card_details_user_primary
ON public.members_card_details (user_id)
WHERE is_primary = true;

-- Step 12: Create index for the trusted partner paystack_recipient_code column
CREATE INDEX IF NOT EXISTS idx_trusted_partner_bank_accounts_paystack_recipient_code
ON public.trusted_partner_bank_accounts(paystack_recipient_code);

-- Step 13: Update the trusted partner unique constraint to be more flexible
-- First drop the existing unique constraint
ALTER TABLE public.trusted_partner_bank_accounts
DROP CONSTRAINT IF EXISTS trusted_partner_bank_accounts_user_id_account_number_branch_code_key;

-- Add a new unique constraint that allows multiple accounts per user but prevents exact duplicates
DROP INDEX IF EXISTS trusted_partner_bank_accounts_user_unique_active;
CREATE UNIQUE INDEX trusted_partner_bank_accounts_user_unique_active
ON public.trusted_partner_bank_accounts (user_id)
WHERE is_active = true;