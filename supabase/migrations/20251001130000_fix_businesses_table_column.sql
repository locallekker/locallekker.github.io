-- Fix businesses table column name from owner_user_id to owner_member_id
-- This migration addresses the remaining column naming issue after the terminology updates

DO $$
BEGIN
  -- Check if businesses table exists and has the old column name
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'businesses'
  ) THEN
    -- Rename owner_user_id to owner_member_id if it exists
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
      AND table_name = 'businesses'
      AND column_name = 'owner_user_id'
    ) THEN
      ALTER TABLE public.businesses RENAME COLUMN owner_user_id TO owner_member_id;
      RAISE NOTICE 'Renamed businesses.owner_user_id to businesses.owner_member_id';
    END IF;

    -- Ensure the column exists with correct type and constraints
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
      AND table_name = 'businesses'
      AND column_name = 'owner_member_id'
    ) THEN
      ALTER TABLE public.businesses ADD COLUMN owner_member_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;
      RAISE NOTICE 'Added businesses.owner_member_id column';
    END IF;

    -- Update any existing indexes if needed
    IF EXISTS (
      SELECT 1 FROM pg_indexes
      WHERE schemaname = 'public'
      AND tablename = 'businesses'
      AND indexname = 'idx_businesses_owner_user_id'
    ) THEN
      DROP INDEX IF EXISTS public.idx_businesses_owner_user_id;
      CREATE INDEX IF NOT EXISTS idx_businesses_owner_member_id ON public.businesses(owner_member_id);
      RAISE NOTICE 'Updated index from owner_user_id to owner_member_id';
    END IF;
  END IF;
END $$;