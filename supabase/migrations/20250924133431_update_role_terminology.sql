-- Migration: Update role terminology to member/trusted_partner/admin
-- This migration updates the existing database to use correct role names

BEGIN;

-- Update role values in memberships table
UPDATE public.memberships
SET role = 'trusted_partner'
WHERE role = 'merchant';

UPDATE public.memberships
SET role = 'member'
WHERE role = 'user';

-- Update role values in profiles table
UPDATE public.profiles
SET role = 'trusted_partner'
WHERE role = 'merchant';

UPDATE public.profiles
SET role = 'member'
WHERE role = 'user';

-- Update default role in profiles table
ALTER TABLE public.profiles
ALTER COLUMN role SET DEFAULT 'member';

-- Update table comments to reflect new terminology
-- COMMENT ON TABLE public.merchants IS 'Stores trusted partner information for businesses'; -- Table doesn't exist yet
COMMENT ON TABLE public.memberships IS 'Stores user role assignments (member, trusted_partner, admin)';
COMMENT ON COLUMN public.profiles.role IS 'User role: member, trusted_partner, or admin';
COMMENT ON COLUMN public.profiles.category IS 'For members: individual, For trusted_partners: restaurant, retail, etc.';

-- Update RLS policies to use correct terminology
-- DROP POLICY IF EXISTS "Users can view own merchant record" ON public.merchants; -- Table doesn't exist yet
DROP POLICY IF EXISTS "Merchants can view own business" ON public.businesses;
DROP POLICY IF EXISTS "Merchants can update own business" ON public.businesses;

-- Create updated policies with correct terminology
-- CREATE POLICY "Members can view own trusted partner record" ON public.merchants -- Table doesn't exist yet
--   FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Trusted partners can view own business" ON public.businesses
  FOR SELECT USING (auth.uid() = owner_member_id);

CREATE POLICY "Trusted partners can update own business" ON public.businesses
  FOR UPDATE USING (auth.uid() = owner_member_id);

COMMIT;