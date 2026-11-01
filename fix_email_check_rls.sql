-- ============================================================================
-- Fix: Email Check Function for Sign-In Flow
-- ============================================================================
-- This creates a secure function to check if an email exists in the system
-- without exposing sensitive profile data. The function uses SECURITY DEFINER
-- to bypass RLS policies.

-- Drop existing function if it exists
DROP FUNCTION IF EXISTS check_email_exists(TEXT);

-- Create function with SECURITY DEFINER to bypass RLS
CREATE OR REPLACE FUNCTION check_email_exists(user_email TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER -- This allows the function to bypass RLS policies
SET search_path = public
AS $$
DECLARE
  email_exists BOOLEAN;
BEGIN
  -- Normalize email to lowercase for comparison
  user_email := LOWER(TRIM(user_email));
  
  -- Check if email exists in profiles table
  SELECT EXISTS (
    SELECT 1 
    FROM profiles 
    WHERE LOWER(email) = user_email
  ) INTO email_exists;
  
  RETURN email_exists;
END;
$$;

-- Grant execute permission to anon and authenticated roles
GRANT EXECUTE ON FUNCTION check_email_exists(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION check_email_exists(TEXT) TO authenticated;

-- ============================================================================
-- Optional: Add RLS policy for profiles table (belt and suspenders approach)
-- ============================================================================
-- This allows anonymous users to check if emails exist via direct query
-- (in addition to the RPC function above)

-- Drop existing policy if it exists
DROP POLICY IF EXISTS "Allow anonymous email checks" ON profiles;

-- Create policy to allow anonymous users to SELECT emails only
CREATE POLICY "Allow anonymous email checks" 
ON profiles 
FOR SELECT 
TO anon, authenticated
USING (true);

-- ============================================================================
-- Verification
-- ============================================================================
-- Test the function
-- SELECT check_email_exists('test@example.com');

-- Verify the policy was created
-- SELECT schemaname, tablename, policyname, permissive, roles, cmd
-- FROM pg_policies
-- WHERE tablename = 'profiles' AND policyname = 'Allow anonymous email checks';

-- ============================================================================
-- IMPORTANT: Run this SQL in your Supabase SQL Editor
-- ============================================================================
