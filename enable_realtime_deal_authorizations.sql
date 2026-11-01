-- Enable Supabase Realtime on deal_authorizations table
-- This is required for the trusted partner app to receive instant notifications
-- when a member requests a deal authorization.
--
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor)

-- Enable the table for realtime by adding it to the supabase_realtime publication
-- First check if it's already added, then add if not
DO $$
BEGIN
  -- Check if deal_authorizations is already in the realtime publication
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND tablename = 'deal_authorizations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.deal_authorizations;
    RAISE NOTICE 'Added deal_authorizations to supabase_realtime publication';
  ELSE
    RAISE NOTICE 'deal_authorizations already in supabase_realtime publication';
  END IF;
END
$$;

-- Set REPLICA IDENTITY to FULL so that UPDATE events include the full row
-- (needed for filtering by business_id on UPDATE events)
ALTER TABLE public.deal_authorizations REPLICA IDENTITY FULL;

-- Verify the table is in the publication
SELECT * FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
  AND tablename IN ('deal_authorizations', 'notifications');
