-- Migration: Create missing try_cast_double function
-- This function is used by the complete_business_profile RPC to safely cast text to double precision

BEGIN;

-- Create the try_cast_double function that's missing
CREATE OR REPLACE FUNCTION public.try_cast_double(input_text text)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
  -- Try to cast the input to double precision
  BEGIN
    RETURN input_text::double precision;
  EXCEPTION
    WHEN invalid_text_representation THEN
      -- If casting fails, return NULL
      RETURN NULL;
  END;
END;
$$;

COMMIT;