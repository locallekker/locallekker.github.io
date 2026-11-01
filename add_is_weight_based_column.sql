-- Add is_weight_based column to trusted_partner_discounts table
-- This column indicates if the deal is weight-based (priced per kg)

-- Add the column with default value false
ALTER TABLE trusted_partner_discounts
ADD COLUMN IF NOT EXISTS is_weight_based BOOLEAN DEFAULT FALSE NOT NULL;

-- Add comment to explain the column
COMMENT ON COLUMN trusted_partner_discounts.is_weight_based IS 
'Indicates if this deal is weight-based (priced per kg). When true, item_price represents R/kg, and members select quantity in 100g increments.';

-- Verify the column was added
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_name = 'trusted_partner_discounts'
AND column_name = 'is_weight_based';
