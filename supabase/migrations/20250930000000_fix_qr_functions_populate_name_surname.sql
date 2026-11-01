-- Migration: Fix database functions to populate name and surname columns in user_qr_codes
-- Extract name and surname from QR code JSON when inserting/updating records

BEGIN;

-- Update activate_qr_after_payment function to populate name and surname
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
      -- Default to 'basic' for invalid plan types
      valid_plan_type := 'basic';
      RAISE WARNING 'Invalid plan_type "%" provided, defaulting to "basic"', p_plan_type;
  END CASE;

  -- Generate new QR code
  new_qr_code := public.generate_user_qr_code(p_user_id);

  -- Extract name and surname from QR code JSON
  qr_name := (new_qr_code::jsonb->>'name');
  qr_surname := (new_qr_code::jsonb->>'surname');

  -- Delete any existing QR codes for this user (ensure only one per user)
  DELETE FROM public.user_qr_codes WHERE user_id = p_user_id;

  -- Insert new QR code with name and surname
  INSERT INTO public.user_qr_codes (
    user_id,
    qr_code,
    name,
    surname,
    is_active,
    expires_at
  ) VALUES (
    p_user_id,
    new_qr_code,
    qr_name,
    qr_surname,
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
      valid_plan_type, -- Use validated plan type
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
      plan_type = valid_plan_type, -- Update to validated plan type
      status = 'active',
      current_period_start = NOW(),
      current_period_end = NOW() + INTERVAL '1 month',
      last_payment_date = NOW(),
      updated_at = NOW()
    WHERE id = subscription_id;
  END IF;

  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to activate QR code after payment: %', SQLERRM;
END;
$$;

-- Update process_automatic_payment function to populate name and surname
CREATE OR REPLACE FUNCTION public.process_automatic_payment(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_qr_code TEXT;
  subscription_id UUID;
  qr_name TEXT;
  qr_surname TEXT;
BEGIN
  -- Generate new QR code
  new_qr_code := public.generate_user_qr_code(p_user_id);

  -- Extract name and surname from QR code JSON
  qr_name := (new_qr_code::jsonb->>'name');
  qr_surname := (new_qr_code::jsonb->>'surname');

  -- Delete any existing QR codes for this user (ensure only one per user)
  DELETE FROM public.user_qr_codes WHERE user_id = p_user_id;

  -- Insert new QR code with name and surname
  INSERT INTO public.user_qr_codes (
    user_id,
    qr_code,
    name,
    surname,
    is_active,
    expires_at
  ) VALUES (
    p_user_id,
    new_qr_code,
    qr_name,
    qr_surname,
    true,
    NOW() + INTERVAL '1 month'
  );

  -- Update subscription status
  UPDATE public.subscriptions
  SET
    status = 'active',
    current_period_start = NOW(),
    current_period_end = NOW() + INTERVAL '1 month',
    last_payment_date = NOW(),
    updated_at = NOW()
  WHERE user_id = p_user_id;

  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to process automatic payment: %', SQLERRM;
END;
$$;

COMMIT;