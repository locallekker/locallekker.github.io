-- Migration: Add name and surname columns and populate from qr_code JSON
-- Ensures name and surname fields are populated for existing and future records

BEGIN;

-- Create user_qr_codes table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.user_qr_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  qr_code TEXT NOT NULL UNIQUE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add name and surname columns to user_qr_codes if they don't exist
ALTER TABLE public.user_qr_codes
ADD COLUMN IF NOT EXISTS name TEXT,
ADD COLUMN IF NOT EXISTS surname TEXT;

-- Update the generate_user_qr_code function to include name and surname in QR data
CREATE OR REPLACE FUNCTION public.generate_user_qr_code(user_uuid UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  qr_data TEXT;
  user_name TEXT;
  user_surname TEXT;
BEGIN
  -- Get user's name and surname from profiles table
  SELECT p.name, p.surname INTO user_name, user_surname
  FROM public.profiles p
  WHERE p.id = user_uuid;

  -- If no profile found, use defaults
  IF user_name IS NULL THEN
    user_name := 'Unknown';
  END IF;
  IF user_surname IS NULL THEN
    user_surname := 'Unknown';
  END IF;

  -- Generate QR code data as JSON including name and surname
  qr_data := jsonb_build_object(
    'user_id', user_uuid,
    'name', user_name,
    'surname', user_surname,
    'timestamp', extract(epoch from now())::bigint,
    'random', (random() * 999999)::int
  )::TEXT;

  -- Insert or update the QR code record
  INSERT INTO public.user_qr_codes (user_id, qr_code, name, surname, expires_at)
  VALUES (
    user_uuid,
    qr_data,
    user_name,
    user_surname,
    NOW() + INTERVAL '1 year'
  )
  ON CONFLICT (user_id)
  DO UPDATE SET
    qr_code = EXCLUDED.qr_code,
    name = EXCLUDED.name,
    surname = EXCLUDED.surname,
    updated_at = NOW()
  WHERE public.user_qr_codes.user_id = user_uuid;

  RETURN qr_data;
END;
$$;

-- Update existing user_qr_codes records where name or surname is NULL
-- Extract values from the qr_code JSON field
UPDATE public.user_qr_codes
SET
  name = COALESCE(name, qr_code::jsonb->>'name'),
  surname = COALESCE(surname, qr_code::jsonb->>'surname'),
  updated_at = NOW()
WHERE name IS NULL OR surname IS NULL;

COMMIT;