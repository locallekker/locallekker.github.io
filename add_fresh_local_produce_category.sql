-- =====================================================
-- ADD FRESH & LOCAL PRODUCE CATEGORY
-- =====================================================
-- Adds trusted partner opt-in for the "Fresh & Local" produce
-- category and a per-deal delivery flag.

BEGIN;

-- Trusted partner opt-in flag
ALTER TABLE public.businesses
ADD COLUMN IF NOT EXISTS sells_fresh_produce BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.businesses.sells_fresh_produce IS
  'True when the partner has opted into the Fresh & Local produce category';

-- Short summary of the goods this partner sells, shown to members
ALTER TABLE public.businesses
ADD COLUMN IF NOT EXISTS produce_description TEXT;

COMMENT ON COLUMN public.businesses.produce_description IS
  'Brief description of the fresh produce goods this partner sells';

-- Per-deal delivery availability
ALTER TABLE public.trusted_partner_discounts
ADD COLUMN IF NOT EXISTS offers_delivery BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.trusted_partner_discounts.offers_delivery IS
  'True when the trusted partner delivers this specific deal/item';

-- Partial index: member listing only ever queries opted-in partners
CREATE INDEX IF NOT EXISTS idx_businesses_sells_fresh_produce
  ON public.businesses(sells_fresh_produce)
  WHERE sells_fresh_produce = true;

COMMIT;

-- Verification query
SELECT
  'Fresh & Local Columns Check' as verification,
  table_name,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE (table_name = 'businesses'
       AND column_name IN ('sells_fresh_produce', 'produce_description'))
   OR (table_name = 'trusted_partner_discounts'
       AND column_name = 'offers_delivery')
ORDER BY table_name, column_name;

-- Check index
SELECT
  'Fresh Produce Index Check' as verification,
  indexname,
  tablename
FROM pg_indexes
WHERE tablename = 'businesses'
  AND indexname = 'idx_businesses_sells_fresh_produce';
