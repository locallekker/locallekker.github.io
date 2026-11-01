-- Function to check if email exists in profiles table
-- This bypasses RLS since it's SECURITY DEFINER
CREATE OR REPLACE FUNCTION public.check_email_exists(user_email TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check if email exists in profiles table
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE email = user_email
  );
END;
$$;