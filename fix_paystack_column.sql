-- Fix missing paystack_subaccount_id column in trusted_partners table
-- Run this in Supabase SQL Editor if the column is missing

-- Add the missing column
ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS paystack_subaccount_id TEXT;

-- Add comment for documentation
COMMENT ON COLUMN public.trusted_partners.paystack_subaccount_id IS 'Paystack subaccount ID for split payments (secure token)';

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_trusted_partners_paystack_subaccount_id ON public.trusted_partners(paystack_subaccount_id);

-- Verify the column was added
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'trusted_partners'
AND column_name = 'paystack_subaccount_id';