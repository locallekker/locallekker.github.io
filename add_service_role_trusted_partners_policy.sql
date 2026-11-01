
-- Migration: Add service role policy for trusted_partners inserts
-- This allows the trigger function to create trusted_partner records

BEGIN;

-- Add service role policy for trusted_partners table
CREATE POLICY \
Service
role
can
insert
trusted_partners\ ON public.trusted_partners
    FOR INSERT
    WITH CHECK (auth.role() = 'service_role');

-- Ensure service role can manage all operations on trusted_partners
CREATE POLICY \Service
role
can
manage
trusted_partners\ ON public.trusted_partners
    FOR ALL
    USING (auth.role() = 'service_role');

COMMIT;

