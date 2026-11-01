-- Check and enforce the 3 valid roles: admin, trusted_partner, member

-- First, check current roles in the system
SELECT
    'Current roles in memberships' as check_type,
    role,
    COUNT(*) as count
FROM public.memberships
GROUP BY role
ORDER BY role;

-- Check if there are any invalid roles
SELECT
    'Invalid roles found' as check_type,
    role,
    COUNT(*) as count
FROM public.memberships
WHERE role NOT IN ('admin', 'trusted_partner', 'member')
GROUP BY role;

-- Check if there are any invalid roles in profiles
SELECT
    'Invalid roles in profiles' as check_type,
    role,
    COUNT(*) as count
FROM public.profiles
WHERE role NOT IN ('admin', 'trusted_partner', 'member')
GROUP BY role;

-- Update any invalid roles to 'member' (safe default)
UPDATE public.memberships
SET role = 'member'
WHERE role NOT IN ('admin', 'trusted_partner', 'member');

UPDATE public.profiles
SET role = 'member'
WHERE role NOT IN ('admin', 'trusted_partner', 'member');

-- Add check constraint to ensure only valid roles (if not already exists)
-- First check if constraint exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'memberships_role_check'
        AND conrelid = 'public.memberships'::regclass
    ) THEN
        ALTER TABLE public.memberships
        ADD CONSTRAINT memberships_role_check
        CHECK (role IN ('admin', 'trusted_partner', 'member'));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'profiles_role_check'
        AND conrelid = 'public.profiles'::regclass
    ) THEN
        ALTER TABLE public.profiles
        ADD CONSTRAINT profiles_role_check
        CHECK (role IN ('admin', 'trusted_partner', 'member'));
    END IF;
END $$;

-- Verify the constraints were added
SELECT
    'Role constraints' as check_type,
    conname as constraint_name,
    conrelid::regclass as table_name,
    pg_get_constraintdef(oid) as constraint_definition
FROM pg_constraint
WHERE conname IN ('memberships_role_check', 'profiles_role_check')
ORDER BY conname;

-- Final verification of valid roles only
SELECT
    'Final role verification - memberships' as check_type,
    role,
    COUNT(*) as count
FROM public.memberships
GROUP BY role
ORDER BY role;

SELECT
    'Final role verification - profiles' as check_type,
    role,
    COUNT(*) as count
FROM public.profiles
GROUP BY role
ORDER BY role;

-- Create function to map user_type to role and ensure valid roles only
CREATE OR REPLACE FUNCTION public.handle_user_role_assignment()
RETURNS TRIGGER AS $$
DECLARE
    user_type TEXT;
    assigned_role TEXT;
BEGIN
    -- Get user_type from auth.users metadata
    SELECT COALESCE(raw_user_meta_data->>'user_type', raw_app_meta_data->>'user_type')
    INTO user_type
    FROM auth.users
    WHERE id = NEW.user_id;

    -- Map user_type to role
    CASE LOWER(COALESCE(user_type, ''))
        WHEN 'trusted_partner' THEN assigned_role := 'trusted_partner';
        WHEN 'admin' THEN assigned_role := 'admin';
        ELSE assigned_role := 'member'; -- Default for 'user' or any other type
    END CASE;

    -- Ensure role is valid (shouldn't be necessary with check constraint, but defensive)
    IF assigned_role NOT IN ('admin', 'trusted_partner', 'member') THEN
        assigned_role := 'member';
    END IF;

    -- Set the role
    NEW.role := assigned_role;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Create trigger to automatically assign roles on membership insert
DROP TRIGGER IF EXISTS trigger_handle_user_role_assignment ON public.memberships;
CREATE TRIGGER trigger_handle_user_role_assignment
    BEFORE INSERT ON public.memberships
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_user_role_assignment();

-- Also create a function to handle profile role assignment
CREATE OR REPLACE FUNCTION public.handle_profile_role_assignment()
RETURNS TRIGGER AS $$
DECLARE
    user_type TEXT;
    assigned_role TEXT;
BEGIN
    -- Get user_type from auth.users metadata
    SELECT COALESCE(raw_user_meta_data->>'user_type', raw_app_meta_data->>'user_type')
    INTO user_type
    FROM auth.users
    WHERE id = NEW.id;

    -- Map user_type to role
    CASE LOWER(COALESCE(user_type, ''))
        WHEN 'trusted_partner' THEN assigned_role := 'trusted_partner';
        WHEN 'admin' THEN assigned_role := 'admin';
        ELSE assigned_role := 'member'; -- Default for 'user' or any other type
    END CASE;

    -- Ensure role is valid
    IF assigned_role NOT IN ('admin', 'trusted_partner', 'member') THEN
        assigned_role := 'member';
    END IF;

    -- Set the role (only if not already set)
    IF NEW.role IS NULL THEN
        NEW.role := assigned_role;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Create trigger for profile role assignment
DROP TRIGGER IF EXISTS trigger_handle_profile_role_assignment ON public.profiles;
CREATE TRIGGER trigger_handle_profile_role_assignment
    BEFORE INSERT ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_profile_role_assignment();