-- =============================================================================
-- COMPREHENSIVE SCHEMA FOR LOCAL LEKKER APP
-- Based on deep analysis of app code and user roles
-- WARNING: This will DROP and RECREATE all tables and data
-- Only use this in development or when resetting the database
-- =============================================================================
-- Tables: memberships, profiles, trusted_partners, businesses, trusted_partner_discounts,
--         deal_authorizations, notifications, processed_bills, payments,
--         user_qr_codes, subscriptions, trusted_partner_bank_accounts
-- =============================================================================

-- WARNING: This will DROP and RECREATE all tables and data
-- Only use this in development or when resetting the database

-- =============================================================================
-- 2. MEMBERSHIPS TABLE - User role assignments
-- =============================================================================
DROP TABLE IF EXISTS public.memberships CASCADE;
CREATE TABLE public.memberships (
    user_id UUID REFERENCES auth.users(id) PRIMARY KEY,
    role TEXT NOT NULL CHECK (role IN ('member', 'trusted_partner', 'admin')),
    gateway TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

-- RLS Policies for memberships
CREATE POLICY "Users can view their own membership" ON public.memberships
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all memberships" ON public.memberships
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.memberships m
            WHERE m.user_id = auth.uid() AND m.role = 'admin'
        )
    );

CREATE POLICY "Admins can update memberships" ON public.memberships
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.memberships m
            WHERE m.user_id = auth.uid() AND m.role = 'admin'
        )
    );

-- =============================================================================
-- 1. PROFILES TABLE - Core user profiles for members and trusted partners
-- =============================================================================
DROP TABLE IF EXISTS public.profiles CASCADE;
CREATE TABLE public.profiles (
    id UUID REFERENCES auth.users(id) PRIMARY KEY,
    name TEXT,
    surname TEXT,
    email TEXT,
    role TEXT CHECK (role IN ('member', 'trusted_partner', 'admin')),
    category TEXT,
    street TEXT,
    suburb TEXT,
    city TEXT,
    province TEXT,
    contact TEXT,
    gender TEXT,
    ethnicity TEXT,
    date_of_birth DATE,
    subscription TEXT DEFAULT 'inactive' CHECK (subscription IN ('active', 'inactive', 'pending', 'cancelled', 'expired')),
    in_app_password TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies for profiles
CREATE POLICY "Users can view their own profile" ON public.profiles
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile" ON public.profiles
    FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Authenticated users can insert their profile" ON public.profiles
    FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Admins can view all profiles" ON public.profiles
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- =============================================================================
-- 3. TRUSTED_PARTNERS TABLE - Business owner profiles
-- =============================================================================
DROP TABLE IF EXISTS public.trusted_partners CASCADE;
CREATE TABLE public.trusted_partners (
    user_id UUID REFERENCES auth.users(id) PRIMARY KEY,
    business_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.trusted_partners ENABLE ROW LEVEL SECURITY;

-- RLS Policies for trusted_partners
CREATE POLICY "Users can view their own trusted_partner record" ON public.trusted_partners
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own trusted_partner record" ON public.trusted_partners
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Authenticated users can insert trusted_partner records" ON public.trusted_partners
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all trusted_partners" ON public.trusted_partners
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- =============================================================================
-- 4. BUSINESSES TABLE - Business entities owned by trusted partners
-- =============================================================================
DROP TABLE IF EXISTS public.businesses CASCADE;
CREATE TABLE public.businesses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_member_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT,
    address TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    contact_email TEXT,
    contact_number TEXT,
    verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(owner_member_id)
);

-- Enable RLS
ALTER TABLE public.businesses ENABLE ROW LEVEL SECURITY;

-- RLS Policies for businesses
CREATE POLICY "Users can view all businesses" ON public.businesses
    FOR SELECT USING (true);

CREATE POLICY "Business owners can update their business" ON public.businesses
    FOR UPDATE USING (owner_member_id = auth.uid());

CREATE POLICY "Authenticated users can create businesses" ON public.businesses
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Admins can manage all businesses" ON public.businesses
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- =============================================================================
-- 12. TRUSTED_PARTNER_BANK_ACCOUNTS TABLE - Banking details for trusted partners
-- =============================================================================
DROP TABLE IF EXISTS public.trusted_partner_bank_accounts CASCADE;
CREATE TABLE public.trusted_partner_bank_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    account_holder_name TEXT NOT NULL,
    bank_name TEXT NOT NULL,
    account_type TEXT NOT NULL CHECK (account_type IN ('checking', 'savings')),
    account_number TEXT NOT NULL,
    branch_code TEXT NOT NULL,
    paystack_public_key TEXT,
    paystack_secret_key TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, account_number, branch_code)
);

-- Enable RLS
ALTER TABLE public.trusted_partner_bank_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own bank accounts" ON public.trusted_partner_bank_accounts
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can insert own bank accounts" ON public.trusted_partner_bank_accounts
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own bank accounts" ON public.trusted_partner_bank_accounts
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Users can delete own bank accounts" ON public.trusted_partner_bank_accounts
    FOR DELETE USING (user_id = auth.uid());

-- =============================================================================
-- 5. TRUSTED_PARTNER_DISCOUNTS TABLE - Discounts offered by businesses
-- =============================================================================
DROP TABLE IF EXISTS public.trusted_partner_discounts CASCADE;
CREATE TABLE public.trusted_partner_discounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trusted_partner_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    item_name TEXT NOT NULL,
    item_price DECIMAL(10,2) NOT NULL,
    percentage DECIMAL(5,2) NOT NULL,
    fixed_amount DECIMAL(10,2),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.trusted_partner_discounts ENABLE ROW LEVEL SECURITY;

-- RLS Policies for trusted_partner_discounts
CREATE POLICY "Users can view all active discounts" ON public.trusted_partner_discounts
    FOR SELECT USING (is_active = true);

CREATE POLICY "Business owners can manage their discounts" ON public.trusted_partner_discounts
    FOR ALL USING (
        business_id IN (
            SELECT id FROM public.businesses
            WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Admins can view all discounts" ON public.trusted_partner_discounts
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- =============================================================================
-- 6. DEAL_AUTHORIZATIONS TABLE - Deal requests from members to businesses
-- =============================================================================
DROP TABLE IF EXISTS public.deal_authorizations CASCADE;
CREATE TABLE public.deal_authorizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    trusted_partner_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE,
    discount_id UUID REFERENCES public.trusted_partner_discounts(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'completed')),
    authorization_type TEXT DEFAULT 'in_store' CHECK (authorization_type IN ('in_store', 'online')),
    payment_method TEXT CHECK (payment_method IN ('in_app', 'pos')),
    amount DECIMAL(10,2),
    notes TEXT,
    rejection_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    approved_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE
);

-- Enable RLS
ALTER TABLE public.deal_authorizations ENABLE ROW LEVEL SECURITY;

-- RLS Policies for deal_authorizations
CREATE POLICY "Members can view their own authorizations" ON public.deal_authorizations
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Members can create their own authorizations" ON public.deal_authorizations
    FOR INSERT WITH CHECK (member_id = auth.uid());

CREATE POLICY "Business owners can view authorizations for their business" ON public.deal_authorizations
    FOR SELECT USING (
        trusted_partner_id IN (
            SELECT id FROM public.businesses
            WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can update authorizations for their business" ON public.deal_authorizations
    FOR UPDATE USING (
        trusted_partner_id IN (
            SELECT id FROM public.businesses
            WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Admins can view all authorizations" ON public.deal_authorizations
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- =============================================================================
-- 7. NOTIFICATIONS TABLE - User notifications system
-- =============================================================================
DROP TABLE IF EXISTS public.notifications CASCADE;
CREATE TABLE public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type TEXT DEFAULT 'info',
    is_read BOOLEAN DEFAULT FALSE,
    data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- RLS Policies for notifications
CREATE POLICY "Users can view their own notifications" ON public.notifications
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can update their own notifications" ON public.notifications
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Authenticated users can insert notifications" ON public.notifications
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Admins can view all notifications" ON public.notifications
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- =============================================================================
-- 8. PROCESSED_BILLS TABLE - Receipt processing and bill management
-- =============================================================================
DROP TABLE IF EXISTS public.processed_bills CASCADE;
CREATE TABLE public.processed_bills (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    business_id UUID REFERENCES public.businesses(id),
    discount_id UUID REFERENCES public.trusted_partner_discounts(id),
    partner_id UUID REFERENCES auth.users(id), -- trusted partner user id
    bill_url TEXT,
    receipt_data JSONB,
    original_total DECIMAL(10,2),
    discount_amount DECIMAL(10,2) DEFAULT 0,
    discounted_total DECIMAL(10,2),
    status TEXT DEFAULT 'pending',
    payment_method TEXT DEFAULT 'pending',
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.processed_bills ENABLE ROW LEVEL SECURITY;

-- RLS Policies for processed_bills
CREATE POLICY "Members can view their own bills" ON public.processed_bills
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Members can insert their own bills" ON public.processed_bills
    FOR INSERT WITH CHECK (member_id = auth.uid());

CREATE POLICY "Members can update their own bills" ON public.processed_bills
    FOR UPDATE USING (member_id = auth.uid());

CREATE POLICY "Business owners can view bills for their business" ON public.processed_bills
    FOR SELECT USING (
        business_id IN (
            SELECT id FROM public.businesses
            WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Admins can view all bills" ON public.processed_bills
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- =============================================================================
-- 9. PAYMENTS TABLE - Payment records
-- =============================================================================
DROP TABLE IF EXISTS public.payments CASCADE;
CREATE TABLE public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    amount DECIMAL(10,2) NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'cancelled')),
    payment_method TEXT,
    transaction_id TEXT,
    gateway TEXT,
    gateway_response JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    happened_at TIMESTAMP WITH TIME ZONE
);

-- Enable RLS
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

-- RLS Policies for payments
CREATE POLICY "Members can view their own payments" ON public.payments
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Authenticated users can insert payments" ON public.payments
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Admins can view all payments" ON public.payments
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

CREATE POLICY "Admins can update payments" ON public.payments
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- =============================================================================
-- 10. USER_QR_CODES TABLE - QR codes for users
-- =============================================================================
DROP TABLE IF EXISTS public.user_qr_codes CASCADE;
CREATE TABLE public.user_qr_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    qr_code TEXT NOT NULL,
    name TEXT,
    surname TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, is_active) -- Only one active QR code per user
);

-- Enable RLS
ALTER TABLE public.user_qr_codes ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_qr_codes
CREATE POLICY "Users can view their own QR codes" ON public.user_qr_codes
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can insert their own QR codes" ON public.user_qr_codes
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Admins can view all QR codes" ON public.user_qr_codes
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- =============================================================================
-- 11. SUBSCRIPTIONS TABLE - User subscription management
-- =============================================================================
DROP TABLE IF EXISTS public.subscriptions CASCADE;
CREATE TABLE public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    plan_type TEXT NOT NULL,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'cancelled', 'expired')),
    auto_renew BOOLEAN DEFAULT FALSE,
    current_period_start TIMESTAMP WITH TIME ZONE,
    current_period_end TIMESTAMP WITH TIME ZONE,
    next_payment_date TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for subscriptions
CREATE POLICY "Users can view their own subscriptions" ON public.subscriptions
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can update their own subscriptions" ON public.subscriptions
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Authenticated users can insert subscriptions" ON public.subscriptions
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Admins can view all subscriptions" ON public.subscriptions
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- =============================================================================
-- INDEXES FOR PERFORMANCE
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);
CREATE INDEX IF NOT EXISTS idx_memberships_role ON public.memberships(role);
CREATE INDEX IF NOT EXISTS idx_memberships_user_id ON public.memberships(user_id);
CREATE INDEX IF NOT EXISTS idx_businesses_owner_member_id ON public.businesses(owner_member_id);
CREATE INDEX IF NOT EXISTS idx_businesses_verified ON public.businesses(verified);
CREATE INDEX IF NOT EXISTS idx_trusted_partner_discounts_business_id ON public.trusted_partner_discounts(business_id);
CREATE INDEX IF NOT EXISTS idx_trusted_partner_discounts_active ON public.trusted_partner_discounts(is_active);
CREATE INDEX IF NOT EXISTS idx_deal_authorizations_member_id ON public.deal_authorizations(member_id);
CREATE INDEX IF NOT EXISTS idx_deal_authorizations_trusted_partner_id ON public.deal_authorizations(trusted_partner_id);
CREATE INDEX IF NOT EXISTS idx_deal_authorizations_status ON public.deal_authorizations(status);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON public.notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_processed_bills_member_id ON public.processed_bills(member_id);
CREATE INDEX IF NOT EXISTS idx_processed_bills_business_id ON public.processed_bills(business_id);
CREATE INDEX IF NOT EXISTS idx_payments_member_id ON public.payments(member_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON public.payments(status);
CREATE INDEX IF NOT EXISTS idx_user_qr_codes_user_id ON public.user_qr_codes(user_id);
CREATE INDEX IF NOT EXISTS idx_user_qr_codes_is_active ON public.user_qr_codes(is_active);
CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON public.subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON public.subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_trusted_partner_bank_accounts_user_id ON public.trusted_partner_bank_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_trusted_partner_bank_accounts_active ON public.trusted_partner_bank_accounts(is_active);

-- =============================================================================
-- FUNCTIONS AND TRIGGERS
-- =============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update triggers to all tables
CREATE TRIGGER update_memberships_updated_at BEFORE UPDATE ON public.memberships
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_trusted_partners_updated_at BEFORE UPDATE ON public.trusted_partners
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_businesses_updated_at BEFORE UPDATE ON public.businesses
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_trusted_partner_discounts_updated_at BEFORE UPDATE ON public.trusted_partner_discounts
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_deal_authorizations_updated_at BEFORE UPDATE ON public.deal_authorizations
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_notifications_updated_at BEFORE UPDATE ON public.notifications
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_processed_bills_updated_at BEFORE UPDATE ON public.processed_bills
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_payments_updated_at BEFORE UPDATE ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_user_qr_codes_updated_at BEFORE UPDATE ON public.user_qr_codes
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_subscriptions_updated_at BEFORE UPDATE ON public.subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_trusted_partner_bank_accounts_updated_at BEFORE UPDATE ON public.trusted_partner_bank_accounts
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();