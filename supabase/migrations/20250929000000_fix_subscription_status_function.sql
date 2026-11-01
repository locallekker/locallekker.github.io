-- Migration: Fix subscription status function and QR code queries
-- Fixes ambiguous column reference and join issues

BEGIN;

-- Drop the existing function first to allow return type change
DROP FUNCTION IF EXISTS public.get_subscription_status(UUID);

-- Fix the get_subscription_status function to avoid ambiguous column references
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

  -- Get subscription info with table alias to avoid ambiguity
  SELECT s.status, s.auto_renew, s.next_payment_date, s.current_period_end INTO sub_record
  FROM public.subscriptions s
  WHERE s.user_id = p_user_id
  ORDER BY s.created_at DESC
  LIMIT 1;

  -- Calculate days until renewal (based on subscription end date)
  IF sub_record.current_period_end IS NOT NULL THEN
    days_diff := EXTRACT(EPOCH FROM (sub_record.current_period_end - NOW())) / 86400;
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
    CASE WHEN days_diff < 0 THEN true ELSE false END,
    sub_record.current_period_end;
END;
$$;

COMMIT;