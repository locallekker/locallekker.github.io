-- Add trusted partner payment flow enhancements
-- Adds approval workflow, bank accounts, and payment linking

-- Add approval status to processed_bills table
ALTER TABLE processed_bills
ADD COLUMN IF NOT EXISTS approval_status TEXT DEFAULT 'pending'
CHECK (approval_status IN ('pending', 'approved', 'rejected'));

ALTER TABLE processed_bills
ADD COLUMN IF NOT EXISTS approved_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE processed_bills
ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES auth.users(id);

ALTER TABLE processed_bills
ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- Add payment method tracking
ALTER TABLE processed_bills
ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'pending'
CHECK (payment_method IN ('pending', 'in_app', 'physical'));

ALTER TABLE processed_bills
ADD COLUMN IF NOT EXISTS payment_id UUID REFERENCES payments(id);

-- Create trusted_partner_bank_accounts table
CREATE TABLE IF NOT EXISTS trusted_partner_bank_accounts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    account_holder_name TEXT NOT NULL,
    bank_name TEXT NOT NULL,
    account_type TEXT NOT NULL CHECK (account_type IN ('checking', 'savings')),
    account_number TEXT NOT NULL,
    branch_code TEXT NOT NULL,
    payfast_merchant_id TEXT,
    payfast_merchant_key TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, account_number, branch_code)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_trusted_partner_bank_accounts_user_id
ON trusted_partner_bank_accounts(user_id);

CREATE INDEX IF NOT EXISTS idx_trusted_partner_bank_accounts_active
ON trusted_partner_bank_accounts(is_active);

-- Enable RLS
ALTER TABLE trusted_partner_bank_accounts ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view own bank accounts" ON trusted_partner_bank_accounts;
DROP POLICY IF EXISTS "Users can insert own bank accounts" ON trusted_partner_bank_accounts;
DROP POLICY IF EXISTS "Users can update own bank accounts" ON trusted_partner_bank_accounts;
DROP POLICY IF EXISTS "Users can delete own bank accounts" ON trusted_partner_bank_accounts;

-- Create RLS policies for bank accounts
CREATE POLICY "Users can view own bank accounts"
ON trusted_partner_bank_accounts
FOR SELECT USING (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can insert own bank accounts"
ON trusted_partner_bank_accounts
FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can update own bank accounts"
ON trusted_partner_bank_accounts
FOR UPDATE USING (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can delete own bank accounts"
ON trusted_partner_bank_accounts
FOR DELETE USING (user_id = (SELECT auth.uid()));

-- Create bill_approvals table for tracking approval workflow
CREATE TABLE IF NOT EXISTS bill_approvals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    bill_id UUID NOT NULL REFERENCES processed_bills(id) ON DELETE CASCADE,
    partner_id UUID NOT NULL REFERENCES auth.users(id),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected')),
    review_notes TEXT,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(bill_id, partner_id)
);

-- Create indexes for bill approvals
CREATE INDEX IF NOT EXISTS idx_bill_approvals_bill_id ON bill_approvals(bill_id);
CREATE INDEX IF NOT EXISTS idx_bill_approvals_partner_id ON bill_approvals(partner_id);
CREATE INDEX IF NOT EXISTS idx_bill_approvals_status ON bill_approvals(status);

-- Enable RLS for bill approvals
ALTER TABLE bill_approvals ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Partners can view their own approvals" ON bill_approvals;
DROP POLICY IF EXISTS "Partners can insert approvals for their bills" ON bill_approvals;
DROP POLICY IF EXISTS "Partners can update their own approvals" ON bill_approvals;

-- Create RLS policies for bill approvals
CREATE POLICY "Partners can view their own approvals"
ON bill_approvals
FOR SELECT USING (partner_id = (SELECT auth.uid()));

CREATE POLICY "Partners can insert approvals for their bills"
ON bill_approvals
FOR INSERT WITH CHECK (partner_id = (SELECT auth.uid()));

CREATE POLICY "Partners can update their own approvals"
ON bill_approvals
FOR UPDATE USING (partner_id = (SELECT auth.uid()));

-- Create function to automatically create approval records
CREATE OR REPLACE FUNCTION create_bill_approval()
RETURNS TRIGGER AS $$
BEGIN
    -- Insert approval record for the partner (business owner)
    INSERT INTO bill_approvals (bill_id, partner_id)
    SELECT NEW.id, b.owner_member_id
    FROM businesses b
    WHERE b.id = NEW.partner_id::uuid;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- Create trigger to auto-create approval records
DROP TRIGGER IF EXISTS trigger_create_bill_approval ON processed_bills;
CREATE TRIGGER trigger_create_bill_approval
    AFTER INSERT ON processed_bills
    FOR EACH ROW
    EXECUTE FUNCTION create_bill_approval();

-- Create function to update bill approval status
CREATE OR REPLACE FUNCTION update_bill_approval_status()
RETURNS TRIGGER AS $$
BEGIN
    -- Update the processed_bills approval status when approval is updated
    IF NEW.status != OLD.status THEN
        UPDATE processed_bills
        SET
            approval_status = NEW.status,
            approved_at = CASE WHEN NEW.status = 'approved' THEN NOW() ELSE approved_at END,
            approved_by = CASE WHEN NEW.status = 'approved' THEN NEW.partner_id ELSE approved_by END
        WHERE id = NEW.bill_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- Create trigger for approval status updates
DROP TRIGGER IF EXISTS trigger_update_bill_approval_status ON bill_approvals;
CREATE TRIGGER trigger_update_bill_approval_status
    AFTER UPDATE ON bill_approvals
    FOR EACH ROW
    EXECUTE FUNCTION update_bill_approval_status();

-- Create updated_at triggers
CREATE OR REPLACE FUNCTION public.update_trusted_partner_bank_accounts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS update_trusted_partner_bank_accounts_updated_at ON trusted_partner_bank_accounts;
CREATE TRIGGER update_trusted_partner_bank_accounts_updated_at
    BEFORE UPDATE ON trusted_partner_bank_accounts
    FOR EACH ROW
    EXECUTE FUNCTION public.update_trusted_partner_bank_accounts_updated_at();

CREATE OR REPLACE FUNCTION public.update_bill_approvals_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS update_bill_approvals_updated_at ON bill_approvals;
CREATE TRIGGER update_bill_approvals_updated_at
    BEFORE UPDATE ON bill_approvals
    FOR EACH ROW
    EXECUTE FUNCTION public.update_bill_approvals_updated_at();