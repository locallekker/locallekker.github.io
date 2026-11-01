-- =============================================================================
-- UNIFIED SCHEMA & RLS POLICIES FOR LOCAL LEKKER APP
-- =============================================================================
-- This provides a single source of truth for the core tables:
-- processed_bills, deal_authorizations, notifications, businesses
-- =============================================================================

-- =============================================================================
-- 1. BUSINESSES TABLE - Foundation for all partner relationships
-- =============================================================================
-- Ensure businesses table has correct structure
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS owner_member_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS name TEXT NOT NULL;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS verified BOOLEAN DEFAULT FALSE;

-- RLS Policies for businesses
DROP POLICY IF EXISTS "Users can view all businesses" ON businesses;
DROP POLICY IF EXISTS "Business owners can update their business" ON businesses;
DROP POLICY IF EXISTS "Authenticated users can create businesses" ON businesses;

CREATE POLICY "Members can view all businesses" ON businesses
    FOR SELECT USING (true);

CREATE POLICY "Business owners can update their business" ON businesses
    FOR UPDATE USING (owner_member_id = auth.uid());

CREATE POLICY "Authenticated members can create businesses" ON businesses
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- =============================================================================
-- 2. PROCESSED_BILLS TABLE - Bill processing foundation
-- =============================================================================
-- Recreate processed_bills table with correct structure
DROP TABLE IF EXISTS processed_bills CASCADE;

CREATE TABLE processed_bills (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES profiles(id),
    business_id UUID REFERENCES businesses(id), -- Nullable for bills without business match
    bill_url TEXT,
    extracted_data JSONB,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE processed_bills ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Members can view their own bills" ON processed_bills
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Members can insert their own bills" ON processed_bills
    FOR INSERT WITH CHECK (member_id = auth.uid());

CREATE POLICY "Business owners can view bills for their business" ON processed_bills
    FOR SELECT USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- =============================================================================
-- 3. DEAL_AUTHORIZATIONS TABLE - Deal request system
-- =============================================================================
-- Recreate deal_authorizations table with correct structure
DROP TABLE IF EXISTS deal_authorizations CASCADE;

CREATE TABLE deal_authorizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID REFERENCES profiles(id),
    business_id UUID REFERENCES businesses(id),
    trusted_partner_id UUID REFERENCES businesses(id),
    discount_id UUID REFERENCES trusted_partner_discounts(id),
    status TEXT DEFAULT 'pending',
    amount DECIMAL(10,2),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE deal_authorizations ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Members can view their authorizations" ON deal_authorizations
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Members can insert their authorizations" ON deal_authorizations
    FOR INSERT WITH CHECK (member_id = auth.uid());

CREATE POLICY "Business owners can view their authorizations" ON deal_authorizations
    FOR SELECT USING (
        trusted_partner_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can update their authorizations" ON deal_authorizations
    FOR UPDATE USING (
        trusted_partner_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- =============================================================================
-- 4. NOTIFICATIONS TABLE - Notification system
-- =============================================================================
-- Recreate notifications table with correct structure
DROP TABLE IF EXISTS notifications CASCADE;

CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id),
    title TEXT,
    message TEXT,
    type TEXT DEFAULT 'info',
    is_read BOOLEAN DEFAULT FALSE,
    data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Members can view their notifications" ON notifications
    FOR SELECT USING (user_id = auth.uid());

-- Allow authenticated users to insert notifications for any user
-- This is required for TPs to notify members, admins to notify anyone
CREATE POLICY "Authenticated can insert notifications for any user" ON notifications
    FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Members can update their notifications" ON notifications
    FOR UPDATE USING (user_id = auth.uid());

-- =============================================================================
-- 5. TRUSTED_PARTNER_DISCOUNTS TABLE - Discount system
-- =============================================================================
-- Ensure trusted_partner_discounts has correct foreign key to businesses
ALTER TABLE trusted_partner_discounts ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES businesses(id);
-- Update existing records to link discounts to businesses
UPDATE trusted_partner_discounts
SET business_id = businesses.id
FROM businesses
WHERE trusted_partner_discounts.trusted_partner_id = businesses.owner_member_id
AND trusted_partner_discounts.business_id IS NULL;

-- RLS Policies for trusted_partner_discounts
DROP POLICY IF EXISTS "Users can view all discounts" ON trusted_partner_discounts;
DROP POLICY IF EXISTS "Business owners can manage their discounts" ON trusted_partner_discounts;

CREATE POLICY "Members can view all discounts" ON trusted_partner_discounts
    FOR SELECT USING (true);

CREATE POLICY "Business owners can manage their discounts" ON trusted_partner_discounts
    FOR ALL USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================
-- Check all tables have RLS enabled
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE tablename IN ('businesses', 'processed_bills', 'deal_authorizations', 'notifications', 'trusted_partner_discounts')
ORDER BY tablename;

-- Check all policies are in place
SELECT schemaname, tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename IN ('businesses', 'processed_bills', 'deal_authorizations', 'notifications', 'trusted_partner_discounts')
ORDER BY tablename, cmd, policyname;