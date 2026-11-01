-- Add INSERT policy for profiles table to allow authenticated users to create their own profiles
-- This fixes the issue where users are created in auth but profiles fail to insert after OTP verification

BEGIN;

-- Add INSERT policy for profiles table
CREATE POLICY "Users can insert own profile" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

COMMIT;