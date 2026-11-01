-- ============================================================
-- Migration Part 2: RPC function
-- Run this SECOND in Supabase SQL Editor (after Part 1)
-- Uses := assignments to avoid Supabase parser issue with SELECT INTO
-- ============================================================

CREATE OR REPLACE FUNCTION public.confirm_promo_signup(
  p_signup_id UUID,
  p_admin_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $fn$
DECLARE
  v_user_id UUID;
  v_signup_status TEXT;
  v_promotion_id UUID;
  v_free_months INTEGER;
  v_sub_id UUID;
  v_current_end TIMESTAMPTZ;
  v_new_end TIMESTAMPTZ;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_admin_id AND role = 'admin'
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Not authorized');
  END IF;

  v_user_id := (SELECT ps.user_id FROM public.promotion_signups ps WHERE ps.id = p_signup_id);
  v_signup_status := (SELECT ps.status FROM public.promotion_signups ps WHERE ps.id = p_signup_id);
  v_promotion_id := (SELECT ps.promotion_id FROM public.promotion_signups ps WHERE ps.id = p_signup_id);

  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Signup not found');
  END IF;

  IF v_signup_status = 'confirmed' THEN
    RETURN json_build_object('success', false, 'error', 'Already confirmed');
  END IF;

  v_free_months := (SELECT p.free_months FROM public.promotions p WHERE p.id = v_promotion_id);

  IF v_promotion_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.promotions WHERE id = v_promotion_id) THEN
    RETURN json_build_object('success', false, 'error', 'Promotion not found');
  END IF;

  v_sub_id := (SELECT s.id FROM public.subscriptions s WHERE s.user_id = v_user_id ORDER BY s.current_period_end DESC NULLS LAST LIMIT 1);
  v_current_end := (SELECT s.current_period_end FROM public.subscriptions s WHERE s.id = v_sub_id);

  IF v_sub_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'No subscription found for member');
  END IF;

  IF v_free_months IS NULL THEN
    v_new_end := GREATEST(v_current_end, now()) + INTERVAL '100 years';
  ELSE
    v_new_end := GREATEST(v_current_end, now()) + (v_free_months || ' months')::INTERVAL;
  END IF;

  UPDATE public.subscriptions
  SET current_period_end = v_new_end, status = 'active', updated_at = now()
  WHERE id = v_sub_id;

  UPDATE public.user_qr_codes
  SET expires_at = v_new_end, is_active = true, updated_at = now()
  WHERE user_id = v_user_id AND is_active = true;

  UPDATE public.promotion_signups
  SET status = 'confirmed', confirmed_at = now(), confirmed_by = p_admin_id, subscription_extended = true
  WHERE id = p_signup_id;

  RETURN json_build_object(
    'success', true,
    'new_period_end', v_new_end,
    'free_months', v_free_months,
    'member_id', v_user_id
  );
END;
$fn$;
