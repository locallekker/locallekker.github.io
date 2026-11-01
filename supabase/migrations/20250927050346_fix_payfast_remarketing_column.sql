-- Fix PayFast payment failure by adding missing remarketing_id column
-- This resolves the 'Could not find the remarketing_id column' error

-- Add remarketing_id column required by PayFast webhooks
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS remarketing_id TEXT;

-- Add other common PayFast webhook fields for future compatibility
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS pf_payment_id TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS payment_status TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS item_name TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS item_description TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS merchant_id TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS token TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS signature TEXT;

-- Create index on pf_payment_id for PayFast lookups
CREATE INDEX IF NOT EXISTS idx_payments_pf_payment_id ON public.payments(pf_payment_id);