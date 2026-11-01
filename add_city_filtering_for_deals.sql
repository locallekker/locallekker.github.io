-- =============================================================================
-- MIGRATION: Add City-Based Filtering for Deals
-- =============================================================================
-- This migration adds city columns to enable city-specific deal filtering
-- Allows members to see only deals from businesses in their current city
-- =============================================================================

-- Add city column to trusted_partner_discounts table
-- This allows deals to be associated with a specific city
ALTER TABLE trusted_partner_discounts ADD COLUMN IF NOT EXISTS city TEXT;

-- Add city column to businesses table (if not exists)
-- This ensures businesses have a city associated with them
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS city TEXT;

-- Add comment explaining the city-based filtering
COMMENT ON COLUMN trusted_partner_discounts.city IS 
'City where this deal is available. Used for geographic filtering to show members deals in their current location.';

COMMENT ON COLUMN businesses.city IS 
'City where the business is located. Used for geographic filtering.';

-- Create index on city column for faster queries
CREATE INDEX IF NOT EXISTS idx_trusted_partner_discounts_city 
ON trusted_partner_discounts(city);

CREATE INDEX IF NOT EXISTS idx_businesses_city 
ON businesses(city);

-- Update RLS policies to support city-based filtering
-- Members can still view all discounts, but the app will filter client-side by city
DROP POLICY IF EXISTS "Members can view all discounts" ON trusted_partner_discounts;

CREATE POLICY "Members can view all active discounts by city" ON trusted_partner_discounts
    FOR SELECT USING (is_active = true);

-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================
-- Check if columns were added successfully
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'trusted_partner_discounts' 
  AND column_name IN ('city')
ORDER BY column_name;

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'businesses' 
  AND column_name IN ('city')
ORDER BY column_name;

-- Check if indexes were created
SELECT indexname, tablename
FROM pg_indexes
WHERE indexname LIKE 'idx_%city%'
ORDER BY tablename;
