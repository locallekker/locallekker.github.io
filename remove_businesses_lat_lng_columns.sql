-- ========================================
-- REMOVE LATITUDE/LONGITUDE FROM BUSINESSES TABLE
-- Remove unused location columns from businesses
-- Idempotent and safe to re-run
-- ========================================

DO $$
BEGIN
    -- Drop latitude column if it exists
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'businesses'
          AND column_name = 'latitude'
    ) THEN
        ALTER TABLE public.businesses
        DROP COLUMN latitude;
        RAISE NOTICE 'Dropped column latitude from public.businesses.';
    ELSE
        RAISE NOTICE 'Column latitude does not exist; nothing to drop.';
    END IF;

    -- Drop longitude column if it exists
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'businesses'
          AND column_name = 'longitude'
    ) THEN
        ALTER TABLE public.businesses
        DROP COLUMN longitude;
        RAISE NOTICE 'Dropped column longitude from public.businesses.';
    ELSE
        RAISE NOTICE 'Column longitude does not exist; nothing to drop.';
    END IF;
END $$;

-- Verify the changes
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'businesses'
ORDER BY ordinal_position;
