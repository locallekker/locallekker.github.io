-- Verification script to ensure profiles table has all columns needed for member signup
-- The database appears to already be correctly configured, but this script ensures consistency

-- Add missing columns if they don't exist (defensive programming - should already exist)
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS name TEXT,
ADD COLUMN IF NOT EXISTS surname TEXT,
ADD COLUMN IF NOT EXISTS email TEXT,
ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'user' CHECK (role IN ('member', 'trusted_partner', 'admin')),
ADD COLUMN IF NOT EXISTS category TEXT,
ADD COLUMN IF NOT EXISTS street TEXT,
ADD COLUMN IF NOT EXISTS suburb TEXT,
ADD COLUMN IF NOT EXISTS city TEXT,
ADD COLUMN IF NOT EXISTS province TEXT,
ADD COLUMN IF NOT EXISTS contact TEXT,
ADD COLUMN IF NOT EXISTS gender TEXT,
ADD COLUMN IF NOT EXISTS ethnicity TEXT,
ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Ensure date_of_birth column type is correct (should already be timestamp with time zone)
-- This is a no-op if already correct
DO $$
BEGIN
    -- Check if date_of_birth is already the right type
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'profiles'
        AND column_name = 'date_of_birth'
        AND data_type = 'timestamp with time zone'
    ) THEN
        RAISE NOTICE 'date_of_birth column is already correctly typed as timestamp with time zone';
    ELSE
        -- If it's DATE, change it to timestamp with time zone
        ALTER TABLE public.profiles ALTER COLUMN date_of_birth TYPE TIMESTAMP WITH TIME ZONE;
        RAISE NOTICE 'Changed date_of_birth column from DATE to TIMESTAMP WITH TIME ZONE';
    END IF;
END $$;

-- Add comments for clarity
COMMENT ON COLUMN public.profiles.name IS 'Member first name';
COMMENT ON COLUMN public.profiles.surname IS 'Member last name';
COMMENT ON COLUMN public.profiles.email IS 'Member email address';
COMMENT ON COLUMN public.profiles.role IS 'User role: member, trusted_partner, or admin';
COMMENT ON COLUMN public.profiles.street IS 'Street address';
COMMENT ON COLUMN public.profiles.suburb IS 'Suburb/district';
COMMENT ON COLUMN public.profiles.city IS 'City';
COMMENT ON COLUMN public.profiles.province IS 'Province/state';
COMMENT ON COLUMN public.profiles.contact IS 'Contact phone number';
COMMENT ON COLUMN public.profiles.gender IS 'Gender: Male, Female, Other';
COMMENT ON COLUMN public.profiles.ethnicity IS 'Ethnicity classification';
COMMENT ON COLUMN public.profiles.date_of_birth IS 'Date of birth (ISO string from app)';
-- in_app_password removed (deprecated in favor of OTP-based password change flow)

-- Verify the structure
SELECT '=== UPDATED PROFILES TABLE STRUCTURE ===' as info;
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'profiles' AND table_schema = 'public'
ORDER BY ordinal_position;