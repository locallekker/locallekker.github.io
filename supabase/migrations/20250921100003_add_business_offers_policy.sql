-- Add policy to allow users to view business names for offers functionality
-- This enables users to see merchant business names in the offers/browse screen

CREATE POLICY "Users can view business names for offers" ON businesses
    FOR SELECT USING (
        auth.role() = 'authenticated'
    );