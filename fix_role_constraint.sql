-- Fix role constraint to match the intended roles: member, trusted_partner, admin
-- This addresses the "valid_role" constraint violation during member signup

-- Drop the old constraint that only allows 'user', 'merchant', 'admin'
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS valid_role;

-- Add the correct constraint that allows 'member', 'trusted_partner', 'admin'
ALTER TABLE public.profiles
ADD CONSTRAINT valid_role
CHECK (role IN ('member', 'trusted_partner', 'admin'));

-- Also fix the memberships table constraint if it exists
ALTER TABLE public.memberships DROP CONSTRAINT IF EXISTS valid_membership_role;
ALTER TABLE public.memberships
ADD CONSTRAINT valid_membership_role
CHECK (role IN ('member', 'trusted_partner', 'admin'));

-- Update any existing 'user' roles to 'member' for consistency
UPDATE public.profiles SET role = 'member' WHERE role = 'user';
UPDATE public.memberships SET role = 'member' WHERE role = 'user';

-- Update any existing 'merchant' roles to 'trusted_partner' for consistency
UPDATE public.profiles SET role = 'trusted_partner' WHERE role = 'merchant';
UPDATE public.memberships SET role = 'trusted_partner' WHERE role = 'merchant';