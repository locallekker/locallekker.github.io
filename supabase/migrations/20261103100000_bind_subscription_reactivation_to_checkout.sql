BEGIN;

ALTER TABLE public.paystack_subscription_setup_locks
  ADD COLUMN IF NOT EXISTS transaction_reference text;

CREATE UNIQUE INDEX IF NOT EXISTS paystack_subscription_setup_reference_unique
  ON public.paystack_subscription_setup_locks (transaction_reference)
  WHERE transaction_reference IS NOT NULL;

CREATE OR REPLACE FUNCTION public.claim_paystack_subscription_setup(p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_claimed boolean := false;
BEGIN
  IF p_user_id IS NULL
     OR (auth.uid() IS DISTINCT FROM p_user_id AND auth.role() IS DISTINCT FROM 'service_role') THEN
    RETURN false;
  END IF;

  INSERT INTO public.paystack_subscription_setup_locks (user_id, claimed_at, transaction_reference)
  VALUES (p_user_id, clock_timestamp(), NULL)
  ON CONFLICT (user_id) DO UPDATE
  SET claimed_at = EXCLUDED.claimed_at,
      transaction_reference = NULL
  WHERE public.paystack_subscription_setup_locks.claimed_at < clock_timestamp() - INTERVAL '30 minutes'
  RETURNING true INTO v_claimed;

  RETURN COALESCE(v_claimed, false);
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_subscription_renewal(p_subscription_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.subscriptions s
  SET renewal_in_progress_at = clock_timestamp(),
      updated_at = clock_timestamp()
  WHERE s.id = p_subscription_id
    AND (s.user_id = auth.uid() OR auth.role() = 'service_role')
    AND s.status = 'active'
    AND s.auto_renew IS TRUE
    AND s.cancellation_requested_at IS NULL
    AND s.cancelled_at IS NULL
    AND s.current_period_end <= clock_timestamp() + INTERVAL '1 hour'
    AND (
      s.renewal_in_progress_at IS NULL
      OR s.renewal_in_progress_at < clock_timestamp() - INTERVAL '24 hours'
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.subscription_renewals sr
      WHERE sr.subscription_id = s.id
        AND sr.status = 'success'
        AND sr.renewal_date >= s.current_period_end - INTERVAL '1 hour'
        AND sr.renewal_date <= s.current_period_end + INTERVAL '25 hours'
    )
    AND (
      auth.role() = 'service_role'
      OR NOT EXISTS (
        SELECT 1
        FROM public.subscription_renewals sr
        WHERE sr.subscription_id = s.id
          AND sr.payment_method = (
            'renewal_' || s.id::text || '_' ||
            floor(extract(epoch FROM s.current_period_end) * 1000)::bigint::text
          )
          AND sr.error_message ILIKE 'Duplicate Transaction Reference%'
      )
    );

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.register_paystack_subscription_setup_reference(
  p_user_id uuid,
  p_reference text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_registered boolean := false;
BEGIN
  IF p_user_id IS NULL
     OR NULLIF(BTRIM(p_reference), '') IS NULL
     OR (auth.uid() IS DISTINCT FROM p_user_id AND auth.role() IS DISTINCT FROM 'service_role') THEN
    RETURN false;
  END IF;

  UPDATE public.paystack_subscription_setup_locks
  SET transaction_reference = BTRIM(p_reference)
  WHERE user_id = p_user_id
    AND claimed_at >= clock_timestamp() - INTERVAL '30 minutes'
    AND transaction_reference IS NULL
  RETURNING true INTO v_registered;

  RETURN COALESCE(v_registered, false);
END;
$$;

CREATE OR REPLACE FUNCTION public.release_paystack_subscription_setup_for_reference(
  p_user_id uuid,
  p_reference text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL
     OR NULLIF(BTRIM(p_reference), '') IS NULL
     OR (auth.uid() IS DISTINCT FROM p_user_id AND auth.role() IS DISTINCT FROM 'service_role') THEN
    RETURN;
  END IF;

  DELETE FROM public.paystack_subscription_setup_locks
  WHERE user_id = p_user_id AND transaction_reference = BTRIM(p_reference);
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_paystack_subscription_payment_checked(
  p_reference text,
  p_event_type text,
  p_user_id uuid DEFAULT NULL,
  p_subscription_code text DEFAULT NULL,
  p_amount_cents bigint DEFAULT 0,
  p_occurred_at timestamptz DEFAULT NULL,
  p_plan_type text DEFAULT 'subscription',
  p_renewal_charge_cents integer DEFAULT 9900
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cutoff timestamptz;
  v_checkout_started_at timestamptz;
  v_result jsonb;
BEGIN
  IF p_event_type = 'charge.success' AND p_user_id IS NOT NULL THEN
    SELECT CASE
      WHEN s.cancelled_at IS NOT NULL AND s.cancellation_requested_at IS NOT NULL
        THEN LEAST(s.cancelled_at, s.cancellation_requested_at)
      ELSE COALESCE(s.cancelled_at, s.cancellation_requested_at)
    END
    INTO v_cutoff
    FROM public.subscriptions s
    WHERE s.user_id = p_user_id
    ORDER BY s.created_at DESC
    LIMIT 1
    FOR UPDATE;

    IF v_cutoff IS NOT NULL
       AND (p_occurred_at IS NULL OR p_occurred_at > v_cutoff) THEN
      SELECT l.claimed_at INTO v_checkout_started_at
      FROM public.paystack_subscription_setup_locks l
      WHERE l.user_id = p_user_id
        AND l.transaction_reference = NULLIF(BTRIM(p_reference), '')
      FOR UPDATE;

      IF v_checkout_started_at IS NULL OR v_checkout_started_at <= v_cutoff THEN
        INSERT INTO public.paystack_subscription_events (
          paystack_reference, user_id, event_type, amount_cents,
          occurred_at, outcome
        ) VALUES (
          p_reference, p_user_id, p_event_type,
          COALESCE(p_amount_cents, 0), p_occurred_at, 'charge_after_cancellation'
        ) ON CONFLICT (paystack_reference) DO NOTHING;

        RETURN jsonb_build_object(
          'applied', false,
          'reason', 'charge_after_cancellation',
          'user_id', p_user_id
        );
      END IF;
    END IF;
  END IF;

  v_result := public.apply_paystack_subscription_payment(
    p_reference,
    p_event_type,
    p_user_id,
    p_subscription_code,
    p_amount_cents,
    p_occurred_at,
    p_plan_type,
    p_renewal_charge_cents
  );

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.register_paystack_subscription_setup_reference(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_paystack_subscription_setup_reference(uuid, text)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.release_paystack_subscription_setup_for_reference(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.release_paystack_subscription_setup_for_reference(uuid, text)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.apply_paystack_subscription_payment_checked(
  text, text, uuid, text, bigint, timestamptz, text, integer
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_paystack_subscription_payment_checked(
  text, text, uuid, text, bigint, timestamptz, text, integer
) TO service_role;

COMMIT;