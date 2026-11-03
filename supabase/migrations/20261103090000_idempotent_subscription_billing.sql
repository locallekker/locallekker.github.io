BEGIN;

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS cancellation_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS paystack_subscription_created_at timestamptz;

CREATE OR REPLACE VIEW public.pending_payment_reconciliation_candidates AS
SELECT
  p.id AS user_id,
  p.email,
  p.name,
  p.surname,
  p.paystack_customer_code,
  p.created_at,
  c.cancellation_cutoff_at
FROM public.profiles p
LEFT JOIN LATERAL (
  SELECT MAX(CASE
    WHEN s.cancelled_at IS NOT NULL AND s.cancellation_requested_at IS NOT NULL
      THEN LEAST(s.cancelled_at, s.cancellation_requested_at)
    ELSE COALESCE(s.cancelled_at, s.cancellation_requested_at)
  END) AS cancellation_cutoff_at
  FROM public.subscriptions s
  WHERE s.user_id = p.id
) c ON true
WHERE p.role = 'member'
  AND COALESCE(p.is_deactivated, false) = false
  AND COALESCE(p.subscription, 'pending') <> 'active'
  AND p.paystack_customer_code IS NOT NULL
  AND p.member_terms_accepted = true
  AND p.created_at <= now() - INTERVAL '30 minutes'
  AND NOT EXISTS (
    SELECT 1 FROM public.subscriptions s
    WHERE s.user_id = p.id AND s.status = 'active'
  );

CREATE TABLE IF NOT EXISTS public.paystack_subscription_events (
  paystack_reference text PRIMARY KEY,
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  subscription_id uuid REFERENCES public.subscriptions(id) ON DELETE SET NULL,
  subscription_code text,
  event_type text NOT NULL,
  amount_cents bigint NOT NULL DEFAULT 0,
  occurred_at timestamptz,
  outcome text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.paystack_subscription_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.paystack_subscription_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.paystack_subscription_events TO service_role;

CREATE TABLE IF NOT EXISTS public.paystack_subscription_setup_locks (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  claimed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

ALTER TABLE public.paystack_subscription_setup_locks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.paystack_subscription_setup_locks FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.paystack_subscription_setup_locks TO service_role;

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

  INSERT INTO public.paystack_subscription_setup_locks (user_id, claimed_at)
  VALUES (p_user_id, clock_timestamp())
  ON CONFLICT (user_id) DO UPDATE
  SET claimed_at = EXCLUDED.claimed_at
  WHERE public.paystack_subscription_setup_locks.claimed_at < clock_timestamp() - INTERVAL '30 minutes'
  RETURNING true INTO v_claimed;

  RETURN COALESCE(v_claimed, false);
END;
$$;

CREATE OR REPLACE FUNCTION public.release_paystack_subscription_setup(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL
      OR (auth.uid() IS DISTINCT FROM p_user_id AND auth.role() IS DISTINCT FROM 'service_role') THEN
    RETURN;
  END IF;

  DELETE FROM public.paystack_subscription_setup_locks WHERE user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_paystack_subscription_setup(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_paystack_subscription_setup(uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.release_paystack_subscription_setup(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.release_paystack_subscription_setup(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.claim_subscription_renewal(
  p_subscription_id uuid
)
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

CREATE OR REPLACE FUNCTION public.apply_paystack_subscription_payment(
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
  v_subscription public.subscriptions%ROWTYPE;
  v_reference text := NULLIF(BTRIM(p_reference), '');
  v_occurred_at timestamptz := COALESCE(p_occurred_at, clock_timestamp());
  v_period_base timestamptz;
  v_period_end timestamptz;
  v_cancellation_cutoff timestamptz;
  v_preserve_cancellation boolean := false;
  v_rows bigint;
BEGIN
  IF v_reference IS NULL THEN
    RAISE EXCEPTION 'Paystack reference is required';
  END IF;

  IF p_event_type = 'subscription.charge' THEN
    IF NULLIF(BTRIM(p_subscription_code), '') IS NULL THEN
      INSERT INTO public.paystack_subscription_events (
        paystack_reference, subscription_code, event_type, amount_cents,
        occurred_at, outcome
      ) VALUES (
        v_reference, p_subscription_code, p_event_type,
        COALESCE(p_amount_cents, 0), p_occurred_at, 'missing_subscription_code'
      ) ON CONFLICT (paystack_reference) DO UPDATE
      SET subscription_code = EXCLUDED.subscription_code,
          outcome = EXCLUDED.outcome
      WHERE public.paystack_subscription_events.outcome = 'missing_subscription_code';
      RETURN jsonb_build_object('applied', false, 'reason', 'missing_subscription_code');
    END IF;

    SELECT * INTO v_subscription
    FROM public.subscriptions
    WHERE paystack_subscription_code = p_subscription_code
    ORDER BY created_at DESC
    LIMIT 1
    FOR UPDATE;
  ELSIF p_event_type = 'charge.success' THEN
    IF p_user_id IS NULL THEN
      RAISE EXCEPTION 'User ID is required for an initial subscription payment';
    END IF;

    PERFORM 1 FROM public.profiles WHERE id = p_user_id FOR UPDATE;
    SELECT * INTO v_subscription
    FROM public.subscriptions
    WHERE user_id = p_user_id
    ORDER BY created_at DESC
    LIMIT 1
    FOR UPDATE;
  ELSE
    RAISE EXCEPTION 'Unsupported subscription payment event: %', p_event_type;
  END IF;

  INSERT INTO public.paystack_subscription_events (
    paystack_reference, user_id, subscription_id, subscription_code,
    event_type, amount_cents, occurred_at, outcome
  ) VALUES (
    v_reference, COALESCE(v_subscription.user_id, p_user_id),
    v_subscription.id, p_subscription_code, p_event_type,
    COALESCE(p_amount_cents, 0), p_occurred_at, 'received'
  ) ON CONFLICT (paystack_reference) DO UPDATE
  SET user_id = EXCLUDED.user_id,
      subscription_id = EXCLUDED.subscription_id,
      subscription_code = EXCLUDED.subscription_code,
      outcome = 'received'
  WHERE public.paystack_subscription_events.outcome IN (
    'missing_subscription_code', 'subscription_not_found'
  );
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RETURN jsonb_build_object('applied', false, 'reason', 'duplicate_reference');
  END IF;

  IF p_event_type = 'subscription.charge' THEN
    IF v_subscription.id IS NULL THEN
      UPDATE public.paystack_subscription_events
      SET outcome = 'subscription_not_found'
      WHERE paystack_reference = v_reference;
      RETURN jsonb_build_object('applied', false, 'reason', 'subscription_not_found');
    END IF;

    v_cancellation_cutoff := CASE
      WHEN v_subscription.cancelled_at IS NOT NULL
       AND v_subscription.cancellation_requested_at IS NOT NULL
        THEN LEAST(v_subscription.cancelled_at, v_subscription.cancellation_requested_at)
      ELSE COALESCE(v_subscription.cancelled_at, v_subscription.cancellation_requested_at)
    END;
    IF v_subscription.status <> 'active'
       OR v_subscription.auto_renew IS NOT TRUE
       OR v_cancellation_cutoff IS NOT NULL THEN
      IF v_cancellation_cutoff IS NOT NULL
         AND p_occurred_at IS NOT NULL
         AND p_occurred_at <= v_cancellation_cutoff THEN
        v_preserve_cancellation := true;
      ELSE
      UPDATE public.paystack_subscription_events
      SET outcome = 'charge_after_cancellation', user_id = v_subscription.user_id,
          subscription_id = v_subscription.id
      WHERE paystack_reference = v_reference;
      RETURN jsonb_build_object(
        'applied', false, 'reason', 'charge_after_cancellation',
        'user_id', v_subscription.user_id, 'subscription_id', v_subscription.id
      );
      END IF;
    END IF;
  ELSE
    v_cancellation_cutoff := CASE
      WHEN v_subscription.cancelled_at IS NOT NULL
       AND v_subscription.cancellation_requested_at IS NOT NULL
        THEN LEAST(v_subscription.cancelled_at, v_subscription.cancellation_requested_at)
      ELSE COALESCE(v_subscription.cancelled_at, v_subscription.cancellation_requested_at)
    END;
    IF v_subscription.id IS NOT NULL
       AND v_cancellation_cutoff IS NOT NULL
       AND p_occurred_at IS NULL THEN
      UPDATE public.paystack_subscription_events
      SET outcome = 'payment_time_unknown', user_id = v_subscription.user_id,
          subscription_id = v_subscription.id
      WHERE paystack_reference = v_reference;
      RETURN jsonb_build_object('applied', false, 'reason', 'payment_time_unknown');
    END IF;

    IF v_subscription.id IS NOT NULL
       AND v_cancellation_cutoff IS NOT NULL
       AND p_occurred_at <= v_cancellation_cutoff THEN
      v_preserve_cancellation := true;
    END IF;

     IF v_subscription.id IS NOT NULL
       AND v_subscription.status = 'active'
       AND v_subscription.auto_renew IS TRUE
       AND v_subscription.cancelled_at IS NULL
       AND v_subscription.cancellation_requested_at IS NULL THEN
      UPDATE public.paystack_subscription_events
      SET outcome = 'already_active', user_id = v_subscription.user_id,
          subscription_id = v_subscription.id
      WHERE paystack_reference = v_reference;
      RETURN jsonb_build_object('applied', false, 'reason', 'already_active');
    END IF;
  END IF;

  v_period_base := CASE
    WHEN v_subscription.current_period_end > v_occurred_at
      THEN v_subscription.current_period_end
    ELSE v_occurred_at
  END;
  v_period_end := v_period_base + INTERVAL '1 month';

  IF v_subscription.id IS NULL THEN
    INSERT INTO public.subscriptions (
      user_id, plan_type, status, auto_renew, current_period_start,
      current_period_end, renewal_charge_cents, cancelled_at,
      cancellation_requested_at, created_at, updated_at
    ) VALUES (
      p_user_id, COALESCE(NULLIF(p_plan_type, ''), 'subscription'), 'active', true,
      v_occurred_at, v_period_end, COALESCE(p_renewal_charge_cents, 9900),
      NULL, NULL, clock_timestamp(), clock_timestamp()
    ) RETURNING * INTO v_subscription;
  ELSIF v_preserve_cancellation THEN
    UPDATE public.subscriptions
    SET status = 'active',
        auto_renew = false,
        plan_type = COALESCE(NULLIF(p_plan_type, ''), plan_type),
        current_period_start = v_occurred_at,
        current_period_end = v_period_end,
        renewal_charge_cents = COALESCE(p_renewal_charge_cents, renewal_charge_cents),
        updated_at = clock_timestamp()
    WHERE id = v_subscription.id
    RETURNING * INTO v_subscription;
  ELSE
    UPDATE public.subscriptions
    SET status = 'active',
        auto_renew = true,
        plan_type = COALESCE(NULLIF(p_plan_type, ''), plan_type),
        current_period_start = v_occurred_at,
        current_period_end = v_period_end,
        renewal_charge_cents = COALESCE(p_renewal_charge_cents, renewal_charge_cents),
        cancelled_at = NULL,
        cancellation_requested_at = NULL,
        updated_at = clock_timestamp()
    WHERE id = v_subscription.id
    RETURNING * INTO v_subscription;
  END IF;

  UPDATE public.paystack_subscription_events
  SET user_id = v_subscription.user_id,
      subscription_id = v_subscription.id,
      outcome = CASE
        WHEN v_preserve_cancellation THEN 'applied_before_cancellation'
        ELSE 'applied'
      END
  WHERE paystack_reference = v_reference;

  RETURN jsonb_build_object(
    'applied', true,
    'user_id', v_subscription.user_id,
    'subscription_id', v_subscription.id,
    'current_period_end', v_subscription.current_period_end,
    'auto_renew', v_subscription.auto_renew
  );
END;
$$;

REVOKE ALL ON FUNCTION public.apply_paystack_subscription_payment(
  text, text, uuid, text, bigint, timestamptz, text, integer
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_paystack_subscription_payment(
  text, text, uuid, text, bigint, timestamptz, text, integer
) TO service_role;

COMMIT;