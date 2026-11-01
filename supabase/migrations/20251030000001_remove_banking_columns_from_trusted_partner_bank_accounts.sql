-- Remove banking columns from trusted_partner_bank_accounts table
-- Migration: 20251030000001_remove_banking_columns_from_trusted_partner_bank_accounts

-- Remove columns that are now stored in trusted_partners table instead
ALTER TABLE public.trusted_partner_bank_accounts
DROP COLUMN IF EXISTS bank_name;

ALTER TABLE public.trusted_partner_bank_accounts
DROP COLUMN IF EXISTS account_number;

ALTER TABLE public.trusted_partner_bank_accounts
DROP COLUMN IF EXISTS paystack_public_key;

ALTER TABLE public.trusted_partner_bank_accounts
DROP COLUMN IF EXISTS paystack_secret_key;