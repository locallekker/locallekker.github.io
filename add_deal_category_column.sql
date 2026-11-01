-- =====================================================
-- ADD DEAL CATEGORY COLUMN
-- =====================================================
-- Add category column to trusted_partner_discounts table
-- for filtering and organizing deals by type

BEGIN;

-- Add deal_category column if it doesn't exist
ALTER TABLE public.trusted_partner_discounts
ADD COLUMN IF NOT EXISTS deal_category TEXT;

-- Add comment to explain the column
COMMENT ON COLUMN public.trusted_partner_discounts.deal_category IS 
  'Category of the deal: Food and Drink, Entertainment, Grocery and necessities, Retail, Beauty, Home, Health and Fitness, Other';

-- Create index for faster filtering
CREATE INDEX IF NOT EXISTS idx_trusted_partner_discounts_deal_category
  ON public.trusted_partner_discounts(deal_category);

-- Update existing deals to have a default category if null
-- Set to 'Other' for existing deals that don't have a category
UPDATE public.trusted_partner_discounts
SET deal_category = 'Other'
WHERE deal_category IS NULL;

-- Set the default value first
ALTER TABLE public.trusted_partner_discounts
ALTER COLUMN deal_category SET DEFAULT 'Other';

-- Then make the column NOT NULL
ALTER TABLE public.trusted_partner_discounts
ALTER COLUMN deal_category SET NOT NULL;

COMMIT;

-- Verification query
SELECT 
  'Deal Category Column Check' as verification,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'trusted_partner_discounts'
  AND column_name = 'deal_category';

-- Check index
SELECT 
  'Deal Category Index Check' as verification,
  indexname,
  tablename
FROM pg_indexes
WHERE tablename = 'trusted_partner_discounts'
  AND indexname LIKE '%deal_category%';
