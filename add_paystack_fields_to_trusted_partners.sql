-- Create trusted_partners table with Paystack integration
-- This table manages trusted partner businesses with Paystack subaccount integration

-- Create trusted_partners table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.trusted_partners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE,
    owner_member_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    paystack_subaccount_id TEXT,
    business_name TEXT NOT NULL,
    business_type TEXT,
    contact_email TEXT,
    contact_phone TEXT,
    address TEXT,
    city TEXT,
    province TEXT,
    postal_code TEXT,
    tax_number TEXT,
    bank_account_holder TEXT,
    bank_name TEXT,
    bank_account_number TEXT,
    bank_branch_code TEXT,
    bank_account_type TEXT,
    settlement_percentage DECIMAL(5,2) DEFAULT 95.0, -- Default 95% to business, 5% to platform
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add comment for Paystack subaccount field
COMMENT ON COLUMN public.trusted_partners.paystack_subaccount_id IS 'Paystack subaccount ID for split payments (secure token)';

-- Enable RLS
ALTER TABLE public.trusted_partners ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Members can view all trusted partners" ON public.trusted_partners
    FOR SELECT USING (true);

CREATE POLICY "Business owners can manage their trusted partner profile" ON public.trusted_partners
    FOR ALL USING (owner_member_id = auth.uid());

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_trusted_partners_business_id ON public.trusted_partners(business_id);
CREATE INDEX IF NOT EXISTS idx_trusted_partners_owner_member_id ON public.trusted_partners(owner_member_id);
CREATE INDEX IF NOT EXISTS idx_trusted_partners_paystack_subaccount_id ON public.trusted_partners(paystack_subaccount_id);

-- If the table already exists, just add the Paystack field
ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS paystack_subaccount_id TEXT;

COMMENT ON COLUMN public.trusted_partners.paystack_subaccount_id IS 'Paystack subaccount ID for split payments (secure token)';