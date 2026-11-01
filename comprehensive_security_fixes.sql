-- Comprehensive Database Security Fixes
-- This script consolidates all search_path fixes for SECURITY DEFINER functions
-- Run this script to apply all security fixes at once

-- Drop functions that may have signature conflicts before recreating them
DROP FUNCTION IF EXISTS public.get_subscription_status(UUID);
DROP FUNCTION IF EXISTS public.activate_qr_after_payment(UUID);
DROP FUNCTION IF EXISTS public.activate_qr_after_payment(UUID, TEXT, DECIMAL);
DROP FUNCTION IF EXISTS public.get_user_bill_statistics(UUID);
DROP FUNCTION IF EXISTS public.disable_auto_renewal(UUID);
DROP FUNCTION IF EXISTS public.enable_auto_renewal(UUID);
DROP FUNCTION IF EXISTS public.enable_auto_renewal(UUID, TEXT, TEXT);

-- Fix for try_cast_double search_path issue
CREATE OR REPLACE FUNCTION public.try_cast_double(input_text text)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
  -- Try to cast the input to double precision
  BEGIN
    RETURN input_text::double precision;
  EXCEPTION
    WHEN invalid_text_representation THEN
      -- If casting fails, return NULL
      RETURN NULL;
  END;
END;
$$;

-- Fix for get_subscription_status search_path issue
CREATE OR REPLACE FUNCTION public.get_subscription_status(p_user_id UUID)
RETURNS TABLE(
  has_active_qr BOOLEAN,
  qr_expires_at TIMESTAMP WITH TIME ZONE,
  subscription_status TEXT,
  auto_renew BOOLEAN,
  days_until_renewal INTEGER,
  next_payment_date TIMESTAMP WITH TIME ZONE,
  payment_overdue BOOLEAN,
  subscription_end_date TIMESTAMP WITH TIME ZONE
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
  SELECT * INTO sub_record
  FROM public.subscriptions
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  -- Calculate days until renewal
  IF sub_record.next_payment_date IS NOT NULL THEN
    days_diff := EXTRACT(EPOCH FROM (sub_record.next_payment_date - NOW())) / 86400;
  ELSE
    days_diff := NULL;
  END IF;

  -- Return the results
  RETURN QUERY
  SELECT
    COALESCE(qr_record.is_active, false) as has_active_qr,
    qr_record.expires_at as qr_expires_at,
    COALESCE(sub_record.status, 'inactive') as subscription_status,
    COALESCE(sub_record.auto_renew, false) as auto_renew,
    days_diff::INTEGER as days_until_renewal,
    sub_record.next_payment_date,
    CASE WHEN sub_record.next_payment_date < NOW() THEN true ELSE false END as payment_overdue,
    sub_record.created_at + INTERVAL '1 year' as subscription_end_date;
END;
$$;

-- Fix for activate_qr_after_payment search_path issue
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
  valid_plan_type TEXT;
  qr_name TEXT;
  qr_surname TEXT;
BEGIN
  -- Validate and normalize plan_type
  CASE LOWER(TRIM(p_plan_type))
    WHEN 'basic', 'premium', 'annual' THEN
      valid_plan_type := LOWER(TRIM(p_plan_type));
    ELSE
      RAISE EXCEPTION 'Invalid plan type: %', p_plan_type;
  END CASE;

  -- Get user's name and surname from profiles table
  SELECT p.name, p.surname INTO qr_name, qr_surname
  FROM public.profiles p
  WHERE p.id = p_user_id;

  -- Generate new QR code
  new_qr_code := public.generate_user_qr_code(p_user_id);

  -- Insert or update subscription
  INSERT INTO public.subscriptions (
    user_id,
    plan_type,
    status,
    auto_renew,
    next_payment_date,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    valid_plan_type,
    'active',
    true,
    NOW() + INTERVAL '1 month',
    NOW(),
    NOW()
  )
  ON CONFLICT (user_id)
  DO UPDATE SET
    plan_type = EXCLUDED.plan_type,
    status = 'active',
    next_payment_date = EXCLUDED.next_payment_date,
    updated_at = NOW()
  RETURNING id INTO subscription_id;

  -- Insert QR code record
  INSERT INTO public.user_qr_codes (
    user_id,
    qr_code,
    is_active,
    activated_at,
    expires_at,
    name,
    surname,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    new_qr_code,
    true,
    NOW(),
    NOW() + INTERVAL '1 year',
    qr_name,
    qr_surname,
    NOW(),
    NOW()
  )
  ON CONFLICT (user_id)
  DO UPDATE SET
    qr_code = EXCLUDED.qr_code,
    is_active = true,
    activated_at = NOW(),
    expires_at = EXCLUDED.expires_at,
    name = EXCLUDED.name,
    surname = EXCLUDED.surname,
    updated_at = NOW();

  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to activate QR code after payment: %', SQLERRM;
END;
$$;

-- Fix for disable_auto_renewal search_path issue
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

-- Fix for enable_auto_renewal search_path issue
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

-- Fix for update_payments_updated_at search_path issue
CREATE OR REPLACE FUNCTION public.update_payments_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- Fix for update_trusted_partner_bank_accounts_updated_at and update_bill_approvals_updated_at search_path issues
CREATE OR REPLACE FUNCTION public.update_trusted_partner_bank_accounts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE OR REPLACE FUNCTION public.update_bill_approvals_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- Fix for get_admin_dashboard search_path issue
CREATE OR REPLACE FUNCTION public.get_admin_dashboard()
RETURNS json
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  result json;
BEGIN
  SELECT json_build_object(
    'total_users', (SELECT count(*) FROM users),
    'total_merchants', (SELECT count(*) FROM profiles WHERE role = 'merchant'),
    'total_online_purchases', COALESCE((SELECT sum(amount) FROM payments WHERE in_store = false AND payment_status = 'complete'), 0),
    'total_in_store_purchases', COALESCE((SELECT sum(amount) FROM payments WHERE in_store = true AND payment_status = 'complete'), 0)
  ) INTO result;

  RETURN result;
END;
$$;

-- Fix for get_user_bill_statistics search_path issue
CREATE OR REPLACE FUNCTION get_user_bill_statistics(user_uuid UUID)
RETURNS TABLE (
    total_bills BIGINT,
    total_saved DECIMAL(10,2),
    total_spent DECIMAL(10,2),
    most_used_partner TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) as total_bills,
        COALESCE(SUM(discount_amount), 0) as total_saved,
        COALESCE(SUM(original_total), 0) as total_spent,
        (
            SELECT partner_id
            FROM processed_bills pb2
            WHERE pb2.user_id = user_uuid
            GROUP BY partner_id
            ORDER BY COUNT(*) DESC
            LIMIT 1
        ) as most_used_partner
    FROM processed_bills pb
    WHERE pb.user_id = user_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;