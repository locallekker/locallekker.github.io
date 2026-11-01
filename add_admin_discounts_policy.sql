-- Add admin policies to trusted_partner_discounts table
-- This allows admin users to view all discounts for management purposes

-- Admin users (by email) can do everything with discounts
CREATE POLICY "Admin full access to trusted_partner_discounts" ON public.trusted_partner_discounts
FOR ALL USING (auth.jwt() ->> 'email' = 'admin@locallekker.com');