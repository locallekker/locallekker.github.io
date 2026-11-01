-- Add Paystack integration fields to payments table
-- This migration adds secure Paystack reference and raw event storage

ALTER TABLE public.payments
ADD COLUMN IF NOT EXISTS paystack_reference TEXT UNIQUE,
ADD COLUMN IF NOT EXISTS raw_event JSONB;

-- Add comments for documentation
COMMENT ON COLUMN public.payments.paystack_reference IS 'Unique Paystack transaction reference for payment verification';
COMMENT ON COLUMN public.payments.raw_event IS 'Raw Paystack webhook event data for audit and debugging (secured)';

-- Create index for faster lookups by Paystack reference
CREATE INDEX IF NOT EXISTS idx_payments_paystack_reference ON public.payments(paystack_reference);

-- Note: RLS policies already exist for payments table, these new fields inherit the same security