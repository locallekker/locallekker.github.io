-- Create deal_receipts table for storing payment receipts
-- This table tracks all deal authorization payments with full timestamps

CREATE TABLE IF NOT EXISTS public.deal_receipts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  deal_authorization_id UUID NOT NULL REFERENCES public.deal_authorizations(id) ON DELETE CASCADE,
  member_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  trusted_partner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  business_id UUID REFERENCES public.businesses(id) ON DELETE SET NULL,
  
  -- Receipt details
  receipt_number TEXT NOT NULL UNIQUE,
  amount DECIMAL(10,2) NOT NULL,
  payment_method TEXT NOT NULL DEFAULT 'paystack',
  
  -- Business and discount info (denormalized for receipt display)
  business_name TEXT,
  discount_name TEXT,
  member_name TEXT,
  member_email TEXT,
  
  -- Timestamps tracking the full flow
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_deal_receipts_deal_authorization_id 
  ON public.deal_receipts(deal_authorization_id);
CREATE INDEX IF NOT EXISTS idx_deal_receipts_member_id 
  ON public.deal_receipts(member_id);
CREATE INDEX IF NOT EXISTS idx_deal_receipts_trusted_partner_id 
  ON public.deal_receipts(trusted_partner_id);
CREATE INDEX IF NOT EXISTS idx_deal_receipts_receipt_number 
  ON public.deal_receipts(receipt_number);
CREATE INDEX IF NOT EXISTS idx_deal_receipts_created_at 
  ON public.deal_receipts(created_at DESC);

-- Enable RLS
ALTER TABLE public.deal_receipts ENABLE ROW LEVEL SECURITY;

-- RLS Policies for deal_receipts

-- Members can view their own receipts
DROP POLICY IF EXISTS "Members can view their own receipts" ON public.deal_receipts;
CREATE POLICY "Members can view their own receipts" ON public.deal_receipts
  FOR SELECT USING (auth.uid() = member_id);

-- Trusted partners can view receipts for their businesses
DROP POLICY IF EXISTS "Trusted partners can view their business receipts" ON public.deal_receipts;
CREATE POLICY "Trusted partners can view their business receipts" ON public.deal_receipts
  FOR SELECT USING (auth.uid() = trusted_partner_id);

-- System can insert receipts (called from authenticated context)
DROP POLICY IF EXISTS "System can insert receipts" ON public.deal_receipts;
CREATE POLICY "System can insert receipts" ON public.deal_receipts
  FOR INSERT WITH CHECK (auth.uid() = member_id);

-- Add payment_completed_at column to deal_authorizations if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'deal_authorizations' 
    AND column_name = 'payment_completed_at'
  ) THEN
    ALTER TABLE public.deal_authorizations 
    ADD COLUMN payment_completed_at TIMESTAMPTZ;
  END IF;
END $$;

-- Update existing timestamp comment
COMMENT ON COLUMN public.deal_authorizations.created_at IS 'Member request timestamp';
COMMENT ON COLUMN public.deal_authorizations.approved_at IS 'Trusted partner approval timestamp';
COMMENT ON COLUMN public.deal_authorizations.payment_completed_at IS 'Member payment completion timestamp';
COMMENT ON COLUMN public.deal_authorizations.completed_at IS 'Final completion timestamp';

-- Add trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_deal_receipts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_deal_receipts_updated_at_trigger ON public.deal_receipts;
CREATE TRIGGER update_deal_receipts_updated_at_trigger
  BEFORE UPDATE ON public.deal_receipts
  FOR EACH ROW
  EXECUTE FUNCTION public.update_deal_receipts_updated_at();
