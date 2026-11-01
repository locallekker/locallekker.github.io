-- Add payment methods support to profiles table
-- This allows members to save multiple payment methods and select a primary one

-- Add paystack_payment_methods column to store array of payment methods
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS paystack_payment_methods JSONB DEFAULT '[]'::jsonb;

-- Add primary_payment_method_id to track which payment method is primary
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS primary_payment_method_id TEXT;

-- Add comment for documentation
COMMENT ON COLUMN profiles.paystack_payment_methods IS 'Array of saved Paystack payment methods (authorization codes, card details)';
COMMENT ON COLUMN profiles.primary_payment_method_id IS 'ID of the primary payment method used for subscriptions and purchases';

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_profiles_primary_payment_method
ON profiles(primary_payment_method_id);

-- Example of payment method structure stored in paystack_payment_methods:
-- [
--   {
--     "id": "AUTH_abc123",
--     "authorization_code": "AUTH_abc123",
--     "card_type": "visa",
--     "last4": "4242",
--     "exp_month": "12",
--     "exp_year": "2025",
--     "bank": "Test Bank",
--     "added_at": "2024-01-15T10:30:00Z"
--   }
-- ]