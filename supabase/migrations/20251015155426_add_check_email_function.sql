-- Migration: Add check_email_exists function
-- +migrate Up

-- Function to check if email exists in profiles table
-- This bypasses RLS since it's SECURITY DEFINER
CREATE OR REPLACE FUNCTION public.check_email_exists(user_email TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  email_exists BOOLEAN := FALSE;
BEGIN
  -- Check if email exists in profiles table
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE email = user_email
  ) INTO email_exists;

  RETURN email_exists;
END;
$$;

-- +migrate Down

DROP FUNCTION IF EXISTS public.check_email_exists(TEXT);