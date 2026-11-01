-- Remove overly-permissive SELECT policy on trusted_partner_discounts
-- This policy makes all rows visible to everyone and defeats more specific SELECT policies.

BEGIN;

DROP POLICY IF EXISTS "Users can view all discounts" ON public.trusted_partner_discounts;

COMMIT;
