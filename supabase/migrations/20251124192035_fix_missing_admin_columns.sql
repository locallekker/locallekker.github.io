-- Migration: Add missing admin_created and password_set columns to profiles table
-- These columns were dropped when the comprehensive schema was deployed

BEGIN;

-- Add admin_created column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
    AND table_name = 'profiles'
    AND column_name = 'admin_created'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN admin_created BOOLEAN DEFAULT false;
  END IF;
END $$;

-- Add password_set column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
    AND table_name = 'profiles'
    AND column_name = 'password_set'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN password_set BOOLEAN DEFAULT true;
  END IF;
END $$;

-- Set default values for existing records
UPDATE public.profiles
SET admin_created = false
WHERE admin_created IS NULL;

UPDATE public.profiles
SET password_set = true
WHERE password_set IS NULL;

COMMIT;