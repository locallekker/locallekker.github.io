-- Migration: Automatic QR Code Management and Payment Processing
-- Handles automatic payments, QR activation/deactivation, and manual renewal flow

BEGIN;

-- Create payment_schedules table for tracking automatic payments
CREATE TABLE IF NOT EXISTS public.payment_schedules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subscription_id UUID NOT NULL REFERENCES public.subscriptions(id) ON DELETE CASCADE,
  payment_method TEXT NOT NULL,
  payment_method_id TEXT,
  amount DECIMAL(10,2) NOT NULL,
  next_payment_date TIMESTAMP WITH TIME ZONE NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_attempt_date TIMESTAMP WITH TIME ZONE,
  failure_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_payment_schedules_user_id ON public.payment_schedules(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_schedules_next_payment ON public.payment_schedules(next_payment_date);
CREATE INDEX IF NOT EXISTS idx_payment_schedules_active ON public.payment_schedules(is_active) WHERE is_active = true;

-- Enable RLS
ALTER TABLE public.payment_schedules ENABLE ROW LEVEL SECURITY;

-- RLS Policies for payment_schedules
DROP POLICY IF EXISTS "Users can view their own payment schedules" ON public.payment_schedules;
DROP POLICY IF EXISTS "Service role can manage payment schedules" ON public.payment_schedules;

CREATE POLICY "Users can view their own payment schedules" ON public.payment_schedules
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Service role can manage payment schedules" ON public.payment_schedules
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');

-- Function to schedule automatic payment for new auto-renew subscriptions
DROP FUNCTION IF EXISTS public.schedule_automatic_payment(UUID, UUID, TEXT, TEXT, DECIMAL);
CREATE OR REPLACE FUNCTION public.schedule_automatic_payment(
  p_user_id UUID,
  p_subscription_id UUID,
  p_payment_method TEXT,
  p_payment_method_id TEXT,
  p_amount DECIMAL(10,2)
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.payment_schedules (
    user_id,
    subscription_id,
    payment_method,
    payment_method_id,
    amount,
    next_payment_date
  ) VALUES (
    p_user_id,
    p_subscription_id,
    p_payment_method,
    p_payment_method_id,
    p_amount,
    NOW() + INTERVAL '1 month'
  );
END;
$$;

-- Function to process automatic payments
DROP FUNCTION IF EXISTS public.process_automatic_payments();
CREATE OR REPLACE FUNCTION public.process_automatic_payments()
RETURNS TABLE(
  user_id UUID,
  subscription_id UUID,
  success BOOLEAN,
  amount DECIMAL(10,2),
  error_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  schedule_record RECORD;
  payment_success BOOLEAN := false;
  error_msg TEXT := '';
  new_qr_code TEXT;
BEGIN
  -- Process all due automatic payments
  FOR schedule_record IN
    SELECT * FROM public.payment_schedules
    WHERE is_active = true
      AND next_payment_date <= NOW()
      AND failure_count < 3
  LOOP
    BEGIN
      -- Simulate payment processing (integrate with actual payment provider)
      -- For demo purposes, simulate 95% success rate
      payment_success := (random() > 0.05);

      IF payment_success THEN
        -- Generate new QR code
        new_qr_code := public.generate_user_qr_code(schedule_record.user_id);

        -- Activate QR code
        UPDATE public.user_qr_codes
        SET
          qr_code = new_qr_code,
          is_active = true,
          expires_at = NOW() + INTERVAL '1 month',
          updated_at = NOW()
        WHERE user_id = schedule_record.user_id;

        -- Update subscription
        UPDATE public.subscriptions
        SET
          current_period_start = NOW(),
          current_period_end = NOW() + INTERVAL '1 month',
          next_payment_date = NOW() + INTERVAL '1 month',
          last_payment_date = NOW(),
          status = 'active',
          updated_at = NOW()
        WHERE id = schedule_record.subscription_id;

        -- Record successful renewal
        INSERT INTO public.subscription_renewals (
          subscription_id,
          user_id,
          renewal_date,
          amount,
          status,
          payment_method,
          qr_code_updated
        ) VALUES (
          schedule_record.subscription_id,
          schedule_record.user_id,
          NOW(),
          schedule_record.amount,
          'success',
          schedule_record.payment_method,
          true
        );

        -- Reset failure count and schedule next payment
        UPDATE public.payment_schedules
        SET
          next_payment_date = NOW() + INTERVAL '1 month',
          last_attempt_date = NOW(),
          failure_count = 0,
          updated_at = NOW()
        WHERE id = schedule_record.id;

      ELSE
        -- Payment failed
        error_msg := 'Payment processing failed';

        -- Increment failure count
        UPDATE public.payment_schedules
        SET
          failure_count = failure_count + 1,
          last_attempt_date = NOW(),
          updated_at = NOW()
        WHERE id = schedule_record.id;

        -- If too many failures, deactivate
        IF schedule_record.failure_count + 1 >= 3 THEN
          -- Deactivate QR code
          UPDATE public.user_qr_codes
          SET
            is_active = false,
            updated_at = NOW()
          WHERE user_id = schedule_record.user_id;

          -- Update subscription status
          UPDATE public.subscriptions
          SET
            status = 'inactive',
            updated_at = NOW()
          WHERE id = schedule_record.subscription_id;

          -- Deactivate payment schedule
          UPDATE public.payment_schedules
          SET
            is_active = false,
            updated_at = NOW()
          WHERE id = schedule_record.id;
        END IF;

        -- Record failed renewal
        INSERT INTO public.subscription_renewals (
          subscription_id,
          user_id,
          renewal_date,
          amount,
          status,
          payment_method,
          qr_code_updated,
          error_message
        ) VALUES (
          schedule_record.subscription_id,
          schedule_record.user_id,
          NOW(),
          schedule_record.amount,
          'failed',
          schedule_record.payment_method,
          false,
          error_msg
        );

      END IF;

      -- Return result
      RETURN QUERY SELECT
        schedule_record.user_id,
        schedule_record.subscription_id,
        payment_success,
        schedule_record.amount,
        error_msg;

    EXCEPTION WHEN OTHERS THEN
      -- Handle unexpected errors
      error_msg := SQLERRM;

      -- Record error in renewal history
      INSERT INTO public.subscription_renewals (
        subscription_id,
        user_id,
        renewal_date,
        amount,
        status,
        payment_method,
        qr_code_updated,
        error_message
      ) VALUES (
        schedule_record.subscription_id,
        schedule_record.user_id,
        NOW(),
        schedule_record.amount,
        'failed',
        schedule_record.payment_method,
        false,
        error_msg
      );

      RETURN QUERY SELECT
        schedule_record.user_id,
        schedule_record.subscription_id,
        false,
        schedule_record.amount,
        error_msg;
    END;
  END LOOP;
END;
$$;

-- Function to handle manual payment completion and QR activation
DROP FUNCTION IF EXISTS public.activate_qr_after_payment(UUID, TEXT, DECIMAL);
CREATE OR REPLACE FUNCTION public.activate_qr_after_payment(
  p_user_id UUID,
  p_plan_type TEXT,
  p_amount DECIMAL(10,2)
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_qr_code TEXT;
  subscription_id UUID;
BEGIN
  -- Generate new QR code
  new_qr_code := public.generate_user_qr_code(p_user_id);

  -- Delete any existing QR codes for this user (ensure only one per user)
  DELETE FROM public.user_qr_codes WHERE user_id = p_user_id;

  -- Insert new QR code
  INSERT INTO public.user_qr_codes (
    user_id,
    qr_code,
    is_active,
    expires_at
  ) VALUES (
    p_user_id,
    new_qr_code,
    true,
    NOW() + INTERVAL '1 month'
  );

  -- Get or create subscription
  SELECT id INTO subscription_id
  FROM public.subscriptions
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF subscription_id IS NULL THEN
    -- Create new subscription
    INSERT INTO public.subscriptions (
      user_id,
      plan_type,
      auto_renew,
      status,
      current_period_start,
      current_period_end,
      last_payment_date
    ) VALUES (
      p_user_id,
      p_plan_type,
      false, -- Manual payment
      'active',
      NOW(),
      NOW() + INTERVAL '1 month',
      NOW()
    ) RETURNING id INTO subscription_id;
  ELSE
    -- Update existing subscription
    UPDATE public.subscriptions
    SET
      current_period_start = NOW(),
      current_period_end = NOW() + INTERVAL '1 month',
      last_payment_date = NOW(),
      status = 'active',
      updated_at = NOW()
    WHERE id = subscription_id;
  END IF;

  -- Record renewal
  INSERT INTO public.subscription_renewals (
    subscription_id,
    user_id,
    renewal_date,
    amount,
    status,
    qr_code_updated
  ) VALUES (
    subscription_id,
    p_user_id,
    NOW(),
    p_amount,
    'success',
    true
  );

  RETURN true;
END;
$$;

-- Trigger function to automatically activate QR codes after successful payments
CREATE OR REPLACE FUNCTION public.handle_payment_completion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only process completed payments
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    -- Call the QR activation function
    PERFORM public.activate_qr_after_payment(
      NEW.user_id,
      NEW.plan_name,
      NEW.amount
    );
  END IF;

  RETURN NEW;
END;
$$;

-- Create trigger on payments table
DROP TRIGGER IF EXISTS trigger_payment_completion ON public.payments;
CREATE TRIGGER trigger_payment_completion
  AFTER INSERT OR UPDATE ON public.payments
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_payment_completion();

-- Function to get subscription status and renewal info
DROP FUNCTION IF EXISTS public.get_subscription_status(UUID);
CREATE OR REPLACE FUNCTION public.get_subscription_status(p_user_id UUID)
RETURNS TABLE(
  has_active_qr BOOLEAN,
  qr_expires_at TIMESTAMP WITH TIME ZONE,
  subscription_status TEXT,
  auto_renew BOOLEAN,
  days_until_renewal INTEGER,
  next_payment_date TIMESTAMP WITH TIME ZONE,
  payment_overdue BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  qr_record RECORD;
  sub_record RECORD;
  days_diff INTEGER;
BEGIN
  -- Get QR code info
  SELECT is_active, expires_at INTO qr_record
  FROM public.user_qr_codes
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  -- Get subscription info
  SELECT s.status, s.auto_renew, s.next_payment_date INTO sub_record
  FROM public.subscriptions s
  WHERE s.user_id = p_user_id
  ORDER BY s.created_at DESC
  LIMIT 1;

  -- Calculate days until renewal
  IF sub_record.next_payment_date IS NOT NULL THEN
    days_diff := EXTRACT(EPOCH FROM (sub_record.next_payment_date - NOW())) / 86400;
  ELSE
    days_diff := NULL;
  END IF;

  -- Return results
  RETURN QUERY SELECT
    COALESCE(qr_record.is_active, false),
    qr_record.expires_at,
    COALESCE(sub_record.status, 'none'),
    COALESCE(sub_record.auto_renew, false),
    days_diff::INTEGER,
    sub_record.next_payment_date,
    CASE WHEN days_diff < 0 THEN true ELSE false END;
END;
$$;

-- Function to schedule automatic payments when auto-renew is enabled
DROP FUNCTION IF EXISTS public.enable_auto_renewal(UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.enable_auto_renewal(
  p_user_id UUID,
  p_payment_method TEXT,
  p_payment_method_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  subscription_record RECORD;
  schedule_amount DECIMAL(10,2);
BEGIN
  -- Get user's subscription
  SELECT * INTO subscription_record
  FROM public.subscriptions
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF subscription_record.id IS NULL THEN
    RETURN false;
  END IF;

  -- Calculate amount based on plan
  CASE subscription_record.plan_type
    WHEN 'basic' THEN schedule_amount := 99.00;
    WHEN 'premium' THEN schedule_amount := 199.00;
    WHEN 'annual' THEN schedule_amount := 1999.00;
    ELSE schedule_amount := 99.00;
  END CASE;

  -- Update subscription to auto-renew
  UPDATE public.subscriptions
  SET
    auto_renew = true,
    next_payment_date = NOW() + INTERVAL '1 month',
    updated_at = NOW()
  WHERE id = subscription_record.id;

  -- Schedule automatic payments
  PERFORM public.schedule_automatic_payment(
    p_user_id,
    subscription_record.id,
    p_payment_method,
    p_payment_method_id,
    schedule_amount
  );

  RETURN true;
END;
$$;

-- Function to disable auto-renewal
DROP FUNCTION IF EXISTS public.disable_auto_renewal(UUID);
CREATE OR REPLACE FUNCTION public.disable_auto_renewal(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Update subscription
  UPDATE public.subscriptions
  SET
    auto_renew = false,
    next_payment_date = NOW() + INTERVAL '1 month',
    updated_at = NOW()
  WHERE user_id = p_user_id;

  -- Deactivate payment schedule
  UPDATE public.payment_schedules
  SET
    is_active = false,
    updated_at = NOW()
  WHERE user_id = p_user_id;

  RETURN true;
END;
$$;

COMMIT;