-- Migration: Replace trigger with minimal logging version
-- This migration replaces the complex trigger with a simple logging version

BEGIN;

-- Replace the trigger function with a minimal version that just logs
CREATE OR REPLACE FUNCTION public.handle_new_user_role_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_type text;
BEGIN
  -- Just log the signup attempt, don't do any database operations
  RAISE WARNING 'User signup detected: %', NEW.email;

  -- Try to get user_type if available
  user_type := COALESCE(
    NEW.raw_app_meta_data->>'user_type',
    NEW.raw_user_meta_data->>'user_type',
    NEW.user_metadata->>'user_type'
  );

  RAISE WARNING 'User type: %, ID: %', user_type, NEW.id;

  -- Don't do any database operations that might fail
  -- Just return NEW to allow the user creation to proceed

  RETURN NEW;
END;
$$;

COMMIT;