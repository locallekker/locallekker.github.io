-- Create deal authorizations table for in-store purchases
CREATE TABLE IF NOT EXISTS deal_authorizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES profiles(id),
    trusted_partner_id UUID NOT NULL REFERENCES businesses(id),
    discount_id UUID NOT NULL REFERENCES trusted_partner_discounts(id),
    status VARCHAR(50) NOT NULL DEFAULT 'pending', -- pending, approved, rejected, completed
    authorization_type VARCHAR(50) NOT NULL DEFAULT 'in_store', -- in_store, online
    payment_method VARCHAR(50), -- in_app, pos
    amount DECIMAL(10,2),
    notes TEXT,
    rejection_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    approved_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE
);

-- Create virtual receipts table
CREATE TABLE IF NOT EXISTS virtual_receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deal_authorization_id UUID NOT NULL REFERENCES deal_authorizations(id),
    receipt_number VARCHAR(100) UNIQUE NOT NULL,
    receipt_data JSONB NOT NULL,
    qr_code TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create member receipts table (for receipt book)
CREATE TABLE IF NOT EXISTS member_receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES profiles(id),
    virtual_receipt_id UUID REFERENCES virtual_receipts(id),
    receipt_type VARCHAR(50) NOT NULL, -- virtual, physical
    title VARCHAR(255) NOT NULL,
    description TEXT,
    amount DECIMAL(10,2),
    business_name VARCHAR(255),
    receipt_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create notifications table
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id),
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    type VARCHAR(50) NOT NULL DEFAULT 'info', -- info, warning, error, success
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_deal_authorizations_member_id ON deal_authorizations(member_id);
CREATE INDEX IF NOT EXISTS idx_deal_authorizations_trusted_partner_id ON deal_authorizations(trusted_partner_id);
CREATE INDEX IF NOT EXISTS idx_deal_authorizations_status ON deal_authorizations(status);

-- Enable RLS
ALTER TABLE deal_authorizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE virtual_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE member_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- RLS Policies for deal_authorizations
CREATE POLICY "Members can view their own authorizations" ON deal_authorizations
    FOR SELECT USING ((SELECT auth.uid()) = member_id);

CREATE POLICY "Trusted partners can view authorizations for their business" ON deal_authorizations
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM businesses
            WHERE businesses.id = deal_authorizations.trusted_partner_id
            AND businesses.owner_member_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Trusted partners can update authorizations for their business" ON deal_authorizations
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM businesses
            WHERE businesses.id = deal_authorizations.trusted_partner_id
            AND businesses.owner_member_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Members can insert their own authorizations" ON deal_authorizations
    FOR INSERT WITH CHECK ((SELECT auth.uid()) = member_id);

-- RLS Policies for virtual_receipts
CREATE POLICY "Members can view their own virtual receipts" ON virtual_receipts
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM deal_authorizations
            WHERE deal_authorizations.id = virtual_receipts.deal_authorization_id
            AND deal_authorizations.member_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Trusted partners can view virtual receipts for their authorizations" ON virtual_receipts
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM deal_authorizations
            WHERE deal_authorizations.id = virtual_receipts.deal_authorization_id
            AND EXISTS (
                SELECT 1 FROM businesses
                WHERE businesses.id = deal_authorizations.trusted_partner_id
                AND businesses.owner_member_id = (SELECT auth.uid())
            )
        )
    );

-- RLS Policies for member_receipts
CREATE POLICY "Members can view their own receipts" ON member_receipts
    FOR SELECT USING ((SELECT auth.uid()) = member_id);

CREATE POLICY "Members can insert their own receipts" ON member_receipts
    FOR INSERT WITH CHECK ((SELECT auth.uid()) = member_id);

CREATE POLICY "Members can update their own receipts" ON member_receipts
    FOR UPDATE USING ((SELECT auth.uid()) = member_id);

-- RLS Policies for notifications
CREATE POLICY "Users can view their own notifications" ON notifications
    FOR SELECT USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can update their own notifications" ON notifications
    FOR UPDATE USING ((SELECT auth.uid()) = user_id);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- Trigger for deal_authorizations (already exists)
-- CREATE TRIGGER update_deal_authorizations_updated_at
--     BEFORE UPDATE ON deal_authorizations
--     FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();