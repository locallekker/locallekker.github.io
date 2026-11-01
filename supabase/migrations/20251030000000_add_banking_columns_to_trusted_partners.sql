-- Add banking columns to trusted_partners table
-- Migration: 20251030000000_add_banking_columns_to_trusted_partners

-- Add banking-related columns to trusted_partners table
ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS business_name TEXT;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS business_type TEXT;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS contact_email TEXT;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS contact_phone TEXT;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS address TEXT;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS city TEXT;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS province TEXT;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS postal_code TEXT;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS tax_number TEXT;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS bank_account_holder TEXT;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS bank_name TEXT;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS bank_account_number TEXT;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS bank_branch_code TEXT;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS bank_account_type TEXT;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS settlement_percentage DECIMAL(5,2) DEFAULT 95.0;

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;

-- Add Paystack subaccount field
ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS paystack_subaccount_id TEXT;

-- Add comment for Paystack subaccount field
COMMENT ON COLUMN public.trusted_partners.paystack_subaccount_id IS 'Paystack subaccount ID for split payments (secure token)';