-- Add bill_data column to deal_authorizations table
-- This stores structured bill breakdown for accurate savings calculation

ALTER TABLE deal_authorizations
ADD COLUMN IF NOT EXISTS bill_data JSONB;

-- Add comment explaining the structure
COMMENT ON COLUMN deal_authorizations.bill_data IS 'Structured bill breakdown: {original_bill_amount, discount_amount, excluded_items_total, final_amount}';

-- Verify the column was added
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'deal_authorizations'
  AND column_name = 'bill_data';
