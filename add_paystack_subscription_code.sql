-- Add paystack_subscription_code column to subscriptions table
-- This stores the Paystack subscription code (SUB_xxxxx) for tracking auto-renewals

-- Add column if it doesn't exist
ALTER TABLE subscriptions 
ADD COLUMN IF NOT EXISTS paystack_subscription_code TEXT;

-- Create index for faster lookups by subscription code
CREATE INDEX IF NOT EXISTS idx_subscriptions_paystack_code 
ON subscriptions(paystack_subscription_code);

-- Add comment explaining the column
COMMENT ON COLUMN subscriptions.paystack_subscription_code IS 
'Paystack subscription code (SUB_xxxxx) for auto-renewal tracking. Set when subscription is created via Paystack plan.';

-- Verify the column was added
SELECT 
    column_name,
    data_type,
    is_nullable
FROM 
    information_schema.columns
WHERE 
    table_name = 'subscriptions' 
    AND column_name = 'paystack_subscription_code';

-- Check if any existing subscriptions need the code populated
SELECT 
    id,
    user_id,
    created_at,
    current_period_end,
    status,
    paystack_subscription_code
FROM 
    subscriptions
ORDER BY 
    created_at DESC
LIMIT 10;
