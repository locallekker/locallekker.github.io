-- Migration: Create QR codes and enhanced subscriptions system
-- Adds QR code management and subscription renewal tracking

BEGIN;

-- Create user_qr_codes table
CREATE TABLE IF NOT EXISTS public.user_qr_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  qr_code TEXT NOT NULL UNIQUE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create enhanced subscriptions table
CREATE TABLE IF NOT EXISTS public.subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_type TEXT NOT NULL CHECK (plan_type IN ('basic', 'premium', 'annual')),
  auto_renew BOOLEAN NOT NULL DEFAULT false,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'cancelled', 'expired')),
  current_period_start TIMESTAMP WITH TIME ZONE NOT NULL,
  current_period_end TIMESTAMP WITH TIME ZONE NOT NULL,
  cancel_at_period_end BOOLEAN NOT NULL DEFAULT false,
  payment_method_id TEXT,
  last_payment_date TIMESTAMP WITH TIME ZONE,
  next_payment_date TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create subscription_renewals table for tracking renewal history
CREATE TABLE IF NOT EXISTS public.subscription_renewals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id UUID NOT NULL REFERENCES public.subscriptions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  renewal_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  amount DECIMAL(10,2) NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('success', 'failed', 'pending')),
  payment_method TEXT,
  qr_code_updated BOOLEAN NOT NULL DEFAULT false,
  error_message TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_qr_codes_user_id ON public.user_qr_codes(user_id);
CREATE INDEX IF NOT EXISTS idx_user_qr_codes_active ON public.user_qr_codes(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON public.subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON public.subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subscription_renewals_subscription_id ON public.subscription_renewals(subscription_id);

-- Enable RLS
ALTER TABLE public.user_qr_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_renewals ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_qr_codes (only create if they don't exist)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_qr_codes' AND policyname = 'Users can view their own QR codes') THEN
        CREATE POLICY "Users can view their own QR codes" ON public.user_qr_codes
          FOR SELECT USING (auth.uid() = user_id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_qr_codes' AND policyname = 'Users can insert their own QR codes') THEN
        CREATE POLICY "Users can insert their own QR codes" ON public.user_qr_codes
          FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_qr_codes' AND policyname = 'Users can update their own QR codes') THEN
        CREATE POLICY "Users can update their own QR codes" ON public.user_qr_codes
          FOR UPDATE USING (auth.uid() = user_id);
    END IF;
END $$;

-- RLS Policies for subscriptions (only create if they don't exist)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'subscriptions' AND policyname = 'Users can view their own subscriptions') THEN
        CREATE POLICY "Users can view their own subscriptions" ON public.subscriptions
          FOR SELECT USING (auth.uid() = user_id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'subscriptions' AND policyname = 'Users can insert their own subscriptions') THEN
        CREATE POLICY "Users can insert their own subscriptions" ON public.subscriptions
          FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'subscriptions' AND policyname = 'Users can update their own subscriptions') THEN
        CREATE POLICY "Users can update their own subscriptions" ON public.subscriptions
          FOR UPDATE USING (auth.uid() = user_id);
    END IF;
END $$;

-- RLS Policies for subscription_renewals (only create if they don't exist)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'subscription_renewals' AND policyname = 'Users can view their own renewal history') THEN
        CREATE POLICY "Users can view their own renewal history" ON public.subscription_renewals
          FOR SELECT USING (auth.uid() = user_id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'subscription_renewals' AND policyname = 'Service role can manage renewals') THEN
        CREATE POLICY "Service role can manage renewals" ON public.subscription_renewals
          FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
    END IF;
END $$;

-- Function to generate QR code for new user
CREATE OR REPLACE FUNCTION public.generate_user_qr_code(user_uuid UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  qr_data TEXT;
BEGIN
  -- Generate unique QR code data
  qr_data := jsonb_build_object(
    'user_id', user_uuid,
    'timestamp', extract(epoch from now())::bigint,
    'random', (random() * 999999)::int,
    'type', 'user_qr'
  )::text;

  RETURN qr_data;
END;
$$;

-- Function to handle monthly subscription renewal
CREATE OR REPLACE FUNCTION public.process_monthly_renewal()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  sub_record RECORD;
  renewal_success BOOLEAN := false;
  new_qr_code TEXT;
BEGIN
  -- Process all active auto-renew subscriptions that are due
  FOR sub_record IN
    SELECT * FROM public.subscriptions
    WHERE status = 'active'
      AND auto_renew = true
      AND next_payment_date <= NOW()
  LOOP
    -- Attempt payment processing (this would integrate with payment provider)
    -- For now, we'll simulate success/failure randomly
    renewal_success := (random() > 0.1); -- 90% success rate for demo

    -- Record the renewal attempt
    INSERT INTO public.subscription_renewals (
      subscription_id,
      user_id,
      renewal_date,
      amount,
      status,
      payment_method,
      qr_code_updated
    ) VALUES (
      sub_record.id,
      sub_record.user_id,
      NOW(),
      CASE
        WHEN sub_record.plan_type = 'basic' THEN 99.00
        WHEN sub_record.plan_type = 'premium' THEN 199.00
        WHEN sub_record.plan_type = 'annual' THEN 1999.00
        ELSE 99.00
      END,
      CASE WHEN renewal_success THEN 'success' ELSE 'failed' END,
      sub_record.payment_method_id,
      renewal_success
    );

    IF renewal_success THEN
      -- Generate new QR code
      new_qr_code := public.generate_user_qr_code(sub_record.user_id);

      -- Update QR code
      UPDATE public.user_qr_codes
      SET
        qr_code = new_qr_code,
        expires_at = NOW() + INTERVAL '1 month',
        updated_at = NOW()
      WHERE user_id = sub_record.user_id;

      -- Update subscription
      UPDATE public.subscriptions
      SET
        current_period_start = NOW(),
        current_period_end = NOW() + INTERVAL '1 month',
        next_payment_date = NOW() + INTERVAL '1 month',
        last_payment_date = NOW(),
        updated_at = NOW()
      WHERE id = sub_record.id;

    ELSE
      -- Mark QR code as inactive
      UPDATE public.user_qr_codes
      SET
        is_active = false,
        updated_at = NOW()
      WHERE user_id = sub_record.user_id;

      -- Update subscription status
      UPDATE public.subscriptions
      SET
        status = 'inactive',
        updated_at = NOW()
      WHERE id = sub_record.id;
    END IF;
  END LOOP;
END;
$$;

COMMIT;