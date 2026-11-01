-- Add policy to allow users to view active discounts from all merchants
-- This enables the offers/browse functionality

CREATE POLICY "Users can view active discounts from all merchants" ON merchant_discounts
    FOR SELECT USING (
        is_active = true
        AND auth.role() = 'authenticated'
    );