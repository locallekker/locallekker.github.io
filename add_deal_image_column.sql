-- Add image_url column to trusted_partner_discounts table for deal images
ALTER TABLE trusted_partner_discounts ADD COLUMN IF NOT EXISTS image_url TEXT;

-- Update RLS policies to allow image_url access
-- The existing policies should cover this since it's just another column