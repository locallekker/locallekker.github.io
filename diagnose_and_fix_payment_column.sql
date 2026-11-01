-- Comprehensive check and fix for deal_authorizations payment flow

-- 1. Check if payment_completed_at column exists
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'deal_authorizations'
  AND column_name = 'payment_completed_at';

-- 2. If column doesn't exist, add it
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'deal_authorizations' 
    AND column_name = 'payment_completed_at'
  ) THEN
    ALTER TABLE public.deal_authorizations 
    ADD COLUMN payment_completed_at TIMESTAMPTZ;
    
    RAISE NOTICE 'Added payment_completed_at column';
  ELSE
    RAISE NOTICE 'payment_completed_at column already exists';
  END IF;
END $$;

-- 3. Check current column structure
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'deal_authorizations'
ORDER BY ordinal_position;

-- 4. Check the status constraint
SELECT
  conname AS constraint_name,
  pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'deal_authorizations'::regclass
  AND contype = 'c'  -- CHECK constraints
ORDER BY conname;
