-- Add missing columns to deal_authorizations table
-- This fixes the "Could not find the 'payment_method' column" error

ALTER TABLE deal_authorizations
ADD COLUMN IF NOT EXISTS payment_method VARCHAR(50),
ADD COLUMN IF NOT EXISTS amount DECIMAL(10,2),
ADD COLUMN IF NOT EXISTS authorization_type VARCHAR(50) DEFAULT 'in_store',
ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
ADD COLUMN IF NOT EXISTS approved_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP WITH TIME ZONE;

-- Update existing records to have default values
UPDATE deal_authorizations
SET
    payment_method = COALESCE(payment_method, 'pos'),
    authorization_type = COALESCE(authorization_type, 'in_store')
WHERE payment_method IS NULL OR authorization_type IS NULL;