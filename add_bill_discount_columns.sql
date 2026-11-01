-- Add columns for bill discount support
-- Run this in Supabase SQL Editor

-- Add is_bill_discount column
ALTER TABLE trusted_partner_discounts 
ADD COLUMN IF NOT EXISTS is_bill_discount BOOLEAN DEFAULT FALSE NOT NULL;

-- Add bill_discount_data column (JSONB for exclusions and settings)
ALTER TABLE trusted_partner_discounts 
ADD COLUMN IF NOT EXISTS bill_discount_data JSONB DEFAULT NULL;

-- Add comment to describe the structure
COMMENT ON COLUMN trusted_partner_discounts.bill_discount_data IS 
'Stores bill discount configuration including:
{
  "isPercentage": boolean,
  "percentage": number (if percentage),
  "totalDiscount": number (if fixed amount),
  "exclusions": [
    {
      "name": string,
      "amount": number,
      "dayOfWeek": string (Monday-Sunday),
      "recurring": boolean
    }
  ]
}';

-- Verify columns were added
SELECT 
  column_name, 
  data_type, 
  column_default, 
  is_nullable
FROM information_schema.columns
WHERE table_name = 'trusted_partner_discounts' 
  AND column_name IN ('is_bill_discount', 'bill_discount_data')
ORDER BY column_name;
