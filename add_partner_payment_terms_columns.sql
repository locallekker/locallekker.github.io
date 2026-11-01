-- Add payment terms acceptance columns to profiles table for Trusted Partners
-- These track whether the TP has accepted the Paystack/payment gateway terms
-- before they can load banking details.

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS partner_payment_terms_accepted BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS partner_payment_terms_accepted_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS partner_payment_terms_version TEXT;
