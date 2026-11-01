-- Add item_name and item_price columns to trusted_partner_discounts table for deal creation
ALTER TABLE trusted_partner_discounts
ADD COLUMN IF NOT EXISTS item_name TEXT,
ADD COLUMN IF NOT EXISTS item_price DECIMAL(10,2);

-- Update existing records to have default values if needed
UPDATE trusted_partner_discounts
SET item_name = name
WHERE item_name IS NULL;

UPDATE trusted_partner_discounts
SET item_price = 0.00
WHERE item_price IS NULL;

-- Make item_name and item_price NOT NULL after populating defaults
ALTER TABLE trusted_partner_discounts
ALTER COLUMN item_name SET NOT NULL,
ALTER COLUMN item_price SET NOT NULL;