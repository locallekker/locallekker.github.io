-- Migration: Add missing INSERT policies for trigger operations
-- Date: 2025-09-19
-- Description: Add INSERT policies for profiles and memberships to allow trigger operations

BEGIN;

-- Add INSERT policy for profiles table to allow service role operations
-- This is needed for the automatic role assignment trigger
CREATE POLICY "Service role can insert profiles" ON public.profiles
    FOR INSERT
    WITH CHECK (auth.role() = 'service_role');

-- Ensure service role can manage all operations on profiles
CREATE POLICY "Service role can manage profiles" ON public.profiles
    FOR ALL
    USING (auth.role() = 'service_role');

-- For memberships, the existing service role policy should cover INSERT,
-- but let's ensure it's comprehensive
DROP POLICY IF EXISTS "Service role can manage memberships" ON public.memberships;
CREATE POLICY "Service role can manage memberships" ON public.memberships
    FOR ALL
    USING (auth.role() = 'service_role');

COMMIT;