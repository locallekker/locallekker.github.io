-- Add Paystack integration fields to profiles table
-- This migration adds secure Paystack customer and authorization codes to user profiles

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS paystack_customer_code TEXT,
ADD COLUMN IF NOT EXISTS paystack_auth_code TEXT;

-- Add comments for documentation
COMMENT ON COLUMN public.profiles.paystack_customer_code IS 'Paystack customer code for recurring payments (secure token, not raw card data)';
COMMENT ON COLUMN public.profiles.paystack_auth_code IS 'Paystack authorization code for saved payment methods (secure token, not raw card data)';

-- Create index for faster lookups by customer code
CREATE INDEX IF NOT EXISTS idx_profiles_paystack_customer_code ON public.profiles(paystack_customer_code);

-- Note: No RLS policies needed for these fields as they are internal secure tokens
-- Access is controlled by existing profile RLS policies