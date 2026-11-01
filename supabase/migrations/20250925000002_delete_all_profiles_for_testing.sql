-- Migration: Delete all profiles and related records for clean testing
-- This removes all existing profile data so we can test fresh signups

BEGIN;

-- Delete all records from tables that reference profiles
-- Order matters due to foreign key constraints

-- Delete businesses first (references profiles.id via owner_user_id)
DELETE FROM public.businesses;

-- Delete trusted_partners (references profiles.id via user_id)
DELETE FROM public.trusted_partners;

-- Delete memberships (references profiles.id via user_id)
DELETE FROM public.memberships;

-- Finally delete all profiles
DELETE FROM public.profiles;

COMMIT;