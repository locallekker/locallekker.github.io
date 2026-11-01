-- Fix plan_type validation in activate_qr_after_payment function
-- This resolves the check constraint violation error

BEGIN;

-- Update the activate_qr_after_payment function with proper plan_type validation
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
BEGIN
  -- Validate and normalize plan_type to prevent check constraint violations
  CASE LOWER(TRIM(COALESCE(p_plan_type, '')))
    WHEN 'basic' THEN valid_plan_type := 'basic';
    WHEN 'premium' THEN valid_plan_type := 'premium';
    WHEN 'annual' THEN valid_plan_type := 'annual';
    ELSE
      -- Default to 'basic' for any invalid plan type
      valid_plan_type := 'basic';
      RAISE WARNING 'Invalid plan_type "%" provided to activate_qr_after_payment, defaulting to "basic"', COALESCE(p_plan_type, 'NULL');
  END CASE;

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
    -- Create new subscription with validated plan type
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
      valid_plan_type,
      false, -- Manual payment
      'active',
      NOW(),
      NOW() + INTERVAL '1 month',
      NOW()
    ) RETURNING id INTO subscription_id;
  ELSE
    -- Update existing subscription with validated plan type
    UPDATE public.subscriptions
    SET
      plan_type = valid_plan_type,
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

COMMIT;