-- Add subscription column to profiles table
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS subscription TEXT DEFAULT 'inactive'
CHECK (subscription IN ('active', 'inactive', 'pending', 'cancelled', 'expired'));