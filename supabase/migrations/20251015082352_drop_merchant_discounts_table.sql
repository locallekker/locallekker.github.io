-- Drop the old merchant_discounts table since it has been renamed to trusted_partner_discounts
-- This migration ensures no duplicate tables exist

DROP TABLE IF EXISTS public.merchant_discounts CASCADE;
