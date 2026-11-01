-- Add paystack_recipient_code column to trusted_partners table
-- This column stores the Paystack transfer recipient code for banking details

-- Add the missing column
ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS paystack_recipient_code TEXT;

-- Add comment for documentation
COMMENT ON COLUMN public.trusted_partners.paystack_recipient_code IS 'Paystack transfer recipient code for banking details collection';

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_trusted_partners_paystack_recipient_code ON public.trusted_partners(paystack_recipient_code);

-- Verify the column was added
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'trusted_partners'
AND column_name = 'paystack_recipient_code';