-- Add missing columns to deal_authorizations table if they don't exist
-- These columns are needed for proper tracking of authorization lifecycle

-- Check current columns
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'deal_authorizations'
ORDER BY ordinal_position;

-- Add payment_method column if missing
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'deal_authorizations' 
        AND column_name = 'payment_method'
    ) THEN
        ALTER TABLE deal_authorizations 
        ADD COLUMN payment_method TEXT;
        
        RAISE NOTICE 'Added payment_method column';
    END IF;
END $$;

-- Add approved_at column if missing
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'deal_authorizations' 
        AND column_name = 'approved_at'
    ) THEN
        ALTER TABLE deal_authorizations 
        ADD COLUMN approved_at TIMESTAMP WITH TIME ZONE;
        
        RAISE NOTICE 'Added approved_at column';
    END IF;
END $$;

-- Add completed_at column if missing
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'deal_authorizations' 
        AND column_name = 'completed_at'
    ) THEN
        ALTER TABLE deal_authorizations 
        ADD COLUMN completed_at TIMESTAMP WITH TIME ZONE;
        
        RAISE NOTICE 'Added completed_at column';
    END IF;
END $$;

-- Add payment_completed_at column if missing
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'deal_authorizations' 
        AND column_name = 'payment_completed_at'
    ) THEN
        ALTER TABLE deal_authorizations 
        ADD COLUMN payment_completed_at TIMESTAMP WITH TIME ZONE;
        
        RAISE NOTICE 'Added payment_completed_at column';
    END IF;
END $$;

-- Add rejection_reason column if missing
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'deal_authorizations' 
        AND column_name = 'rejection_reason'
    ) THEN
        ALTER TABLE deal_authorizations 
        ADD COLUMN rejection_reason TEXT;
        
        RAISE NOTICE 'Added rejection_reason column';
    END IF;
END $$;

-- Add authorization_type column if missing
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'deal_authorizations' 
        AND column_name = 'authorization_type'
    ) THEN
        ALTER TABLE deal_authorizations 
        ADD COLUMN authorization_type TEXT DEFAULT 'in_store';
        
        RAISE NOTICE 'Added authorization_type column';
    END IF;
END $$;

-- Verify all columns now exist
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'deal_authorizations'
ORDER BY ordinal_position;

-- Show sample data with all fields
SELECT 
    id,
    member_id,
    business_id,
    discount_id,
    status,
    payment_method,
    authorization_type,
    amount,
    notes,
    rejection_reason,
    created_at,
    updated_at,
    approved_at,
    payment_completed_at,
    completed_at
FROM deal_authorizations
ORDER BY created_at DESC
LIMIT 5;
