-- Migration: Fix role assignment issue - convert 'member' to 'user' and add constraints
-- Date: 2025-09-18
-- Description: Fixes the issue where roles were manually set to 'member' instead of 'user'

BEGIN;

-- Step 0: Drop existing constraints that might conflict
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS valid_role;
ALTER TABLE public.memberships DROP CONSTRAINT IF EXISTS valid_membership_role;

-- Step 1: Fix existing 'member' roles to 'user'
-- Update profiles table
UPDATE public.profiles
SET role = 'user'
WHERE role = 'member' OR role IS NULL OR role = '';

-- Update memberships table
UPDATE public.memberships
SET role = 'user'
WHERE role = 'member' OR role IS NULL OR role = '';

-- Step 2: Set default role for new profiles
ALTER TABLE public.profiles
ALTER COLUMN role SET DEFAULT 'user';

-- Step 3: Add check constraints to prevent invalid roles
ALTER TABLE public.profiles
ADD CONSTRAINT valid_role
CHECK (role IN ('user', 'merchant', 'admin'));

ALTER TABLE public.memberships
ADD CONSTRAINT valid_membership_role
CHECK (role IN ('user', 'merchant', 'admin'));

-- Step 4: Create an index on role columns for better performance
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_memberships_role ON public.memberships(role);

COMMIT;

-- Verification queries (run these separately to check the results)
-- SELECT role, COUNT(*) FROM public.profiles GROUP BY role ORDER BY role;
-- SELECT role, COUNT(*) FROM public.memberships GROUP BY role ORDER BY role;