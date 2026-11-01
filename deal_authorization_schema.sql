-- Add in-app password field to profiles table
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS in_app_password TEXT;

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
    type VARCHAR(50) NOT NULL, -- payment_success, deal_approved, pos_payment_request, etc.
    data JSONB,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_deal_authorizations_member_id ON deal_authorizations(member_id);
CREATE INDEX IF NOT EXISTS idx_deal_authorizations_trusted_partner_id ON deal_authorizations(trusted_partner_id);
CREATE INDEX IF NOT EXISTS idx_deal_authorizations_status ON deal_authorizations(status);
CREATE INDEX IF NOT EXISTS idx_member_receipts_member_id ON member_receipts(member_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON notifications(is_read);

-- Add RLS policies
ALTER TABLE deal_authorizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE virtual_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE member_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Drop existing policies before creating new ones
DROP POLICY IF EXISTS "Members can view their own authorizations" ON deal_authorizations;
DROP POLICY IF EXISTS "Trusted partners can view authorizations for their business" ON deal_authorizations;
DROP POLICY IF EXISTS "Trusted partners can update authorizations for their business" ON deal_authorizations;
DROP POLICY IF EXISTS "Members can view receipts for their authorizations" ON virtual_receipts;
DROP POLICY IF EXISTS "Trusted partners can view receipts for their authorizations" ON virtual_receipts;
DROP POLICY IF EXISTS "Members can view their own receipts" ON member_receipts;
DROP POLICY IF EXISTS "Users can view their own notifications" ON notifications;

-- Deal authorizations policies
CREATE POLICY "Members can view their own authorizations" ON deal_authorizations
    FOR SELECT USING (member_id = (SELECT auth.uid()));

CREATE POLICY "Trusted partners can view authorizations for their business" ON deal_authorizations
    FOR SELECT USING (
        trusted_partner_id IN (
            SELECT id FROM businesses WHERE owner_member_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Trusted partners can update authorizations for their business" ON deal_authorizations
    FOR UPDATE USING (
        trusted_partner_id IN (
            SELECT id FROM businesses WHERE owner_member_id = (SELECT auth.uid())
        )
    );

-- Virtual receipts policies
CREATE POLICY "Members can view receipts for their authorizations" ON virtual_receipts
    FOR SELECT USING (
        deal_authorization_id IN (
            SELECT id FROM deal_authorizations WHERE member_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Trusted partners can view receipts for their authorizations" ON virtual_receipts
    FOR SELECT USING (
        deal_authorization_id IN (
            SELECT id FROM deal_authorizations
            WHERE trusted_partner_id IN (
                SELECT id FROM businesses WHERE owner_member_id = (SELECT auth.uid())
            )
        )
    );

-- Member receipts policies
CREATE POLICY "Members can view their own receipts" ON member_receipts
    FOR ALL USING (member_id = (SELECT auth.uid()));

-- Notifications policies
CREATE POLICY "Members can view their own notifications" ON notifications
    FOR ALL USING (user_id = (SELECT auth.uid()));