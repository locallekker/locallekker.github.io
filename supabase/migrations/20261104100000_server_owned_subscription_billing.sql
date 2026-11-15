BEGIN;

ALTER TABLE public.subscriptions
  ADD COLUMN billing_owner text NOT NULL DEFAULT 'migration_pending'
    CHECK (billing_owner IN ('migration_pending', 'paystack', 'server', 'manual')),
  ADD COLUMN billing_cycle_number bigint NOT NULL DEFAULT 0,
  ADD COLUMN billing_interval text NOT NULL DEFAULT '30_days'
    CHECK (billing_interval IN ('30_days', 'calendar_month')),
  ADD COLUMN billing_migration_evidence text,
  ADD COLUMN billing_migrated_at timestamptz;

UPDATE public.subscriptions SET billing_owner = 'paystack'
WHERE NULLIF(BTRIM(paystack_subscription_code), '') IS NOT NULL;

CREATE UNIQUE INDEX subscriptions_one_server_billing_owner
  ON public.subscriptions(user_id) WHERE billing_owner = 'server';

CREATE TABLE public.subscription_billing_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.subscriptions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  cycle_number bigint NOT NULL,
  reference text NOT NULL UNIQUE,
  amount_cents integer NOT NULL CHECK (amount_cents > 0),
  currency text NOT NULL DEFAULT 'ZAR' CHECK (currency = 'ZAR'),
  purpose text NOT NULL CHECK (purpose IN ('subscription', 'subscription_renewal', 'promotion_intro')),
  state text NOT NULL DEFAULT 'ready'
    CHECK (state IN ('ready', 'submitting', 'pending', 'unknown', 'failed', 'paid', 'cancelled')),
  free_months integer,
  lifetime boolean NOT NULL DEFAULT false,
  promotion_id uuid,
  participant_id uuid,
  submitted_at timestamptz,
  provider_transaction_id text UNIQUE,
  authorization_url text,
  paid_at timestamptz,
  failure_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (subscription_id, cycle_number)
);

CREATE TABLE public.subscription_billing_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cycle_id uuid REFERENCES public.subscription_billing_cycles(id) ON DELETE CASCADE,
  subscription_id uuid NOT NULL REFERENCES public.subscriptions(id) ON DELETE CASCADE,
  action text NOT NULL,
  detail text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.subscription_billing_failed_attempts (
  reference text PRIMARY KEY,
  cycle_id uuid NOT NULL REFERENCES public.subscription_billing_cycles(id) ON DELETE CASCADE,
  provider_transaction_id text NOT NULL,
  verified_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.subscription_billing_cycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_billing_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_billing_failed_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.subscription_billing_cycles, public.subscription_billing_audit
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.subscription_billing_failed_attempts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.subscription_billing_cycles TO authenticated;
CREATE POLICY member_read_billing_cycles ON public.subscription_billing_cycles
  FOR SELECT TO authenticated USING (user_id = auth.uid());
GRANT ALL ON public.subscription_billing_cycles, public.subscription_billing_audit TO service_role;
GRANT ALL ON public.subscription_billing_failed_attempts TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.subscription_billing_audit_id_seq TO service_role;

CREATE FUNCTION public.guard_unresolved_billing_deletion()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF OLD.state IN ('submitting', 'pending', 'unknown') THEN
    RAISE EXCEPTION 'Reconcile the in-flight membership payment before deleting this account';
  END IF;
  RETURN OLD;
END;
$$;
CREATE TRIGGER guard_unresolved_billing_deletion BEFORE DELETE ON public.subscription_billing_cycles
FOR EACH ROW EXECUTE FUNCTION public.guard_unresolved_billing_deletion();

-- Existing accounts require an audited provider reconciliation, even without a saved SUB code.
CREATE FUNCTION public.enable_server_subscription_billing(
  p_subscription_id uuid, p_evidence text, p_interval text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_sub public.subscriptions%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Service role required';
  END IF;
  IF NULLIF(BTRIM(p_evidence), '') IS NULL
     OR p_interval IS NULL OR p_interval NOT IN ('30_days', 'calendar_month') THEN
    RAISE EXCEPTION 'Provider reconciliation evidence and billing interval are required';
  END IF;
  SELECT * INTO STRICT v_sub FROM public.subscriptions WHERE id = p_subscription_id FOR UPDATE;
  IF v_sub.renewal_in_progress_at IS NOT NULL OR EXISTS (
    SELECT 1 FROM public.subscription_billing_cycles
    WHERE subscription_id = v_sub.id AND state IN ('submitting', 'pending', 'unknown')
  ) THEN
    RAISE EXCEPTION 'Resolve in-flight payments before migration';
  END IF;
  UPDATE public.subscriptions
  SET billing_owner = 'server', billing_interval = p_interval,
      paystack_subscription_code = NULL,
      billing_migration_evidence = p_evidence, billing_migrated_at = clock_timestamp()
  WHERE id = p_subscription_id;
  INSERT INTO public.subscription_billing_audit(subscription_id, action, detail)
  VALUES (p_subscription_id, 'billing_owner_enabled', p_evidence);
END;
$$;

CREATE FUNCTION public.prepare_subscription_billing(
  p_user_id uuid, p_automatic boolean DEFAULT false,
  p_promotion_id uuid DEFAULT NULL, p_participant_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_sub public.subscriptions%ROWTYPE;
  v_cycle public.subscription_billing_cycles%ROWTYPE;
  v_email text;
  v_amount integer;
  v_free_months integer;
  v_lifetime boolean := false;
  v_purpose text;
  v_id uuid := gen_random_uuid();
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
  SELECT email INTO STRICT v_email FROM public.profiles WHERE id = p_user_id FOR UPDATE;
  SELECT * INTO v_sub FROM public.subscriptions WHERE user_id = p_user_id
  ORDER BY created_at DESC LIMIT 1 FOR UPDATE;

  IF v_sub.id IS NULL THEN
    IF p_automatic THEN RAISE EXCEPTION 'No subscription to renew'; END IF;
    IF EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id AND subscription = 'active') THEN
      RAISE EXCEPTION 'billing_migration_required: Existing membership requires reconciliation';
    END IF;
    INSERT INTO public.subscriptions(user_id, plan_type, status, auto_renew,
      current_period_start, current_period_end, renewal_charge_cents, billing_owner, billing_interval)
    VALUES (p_user_id, 'subscription', 'inactive', true,
      clock_timestamp(), clock_timestamp(), 9900, 'server', 'calendar_month')
    RETURNING * INTO v_sub;
  END IF;
  IF v_sub.billing_owner <> 'server' OR NULLIF(BTRIM(v_sub.paystack_subscription_code), '') IS NOT NULL THEN
    RAISE EXCEPTION 'billing_migration_required: Provider subscription must be reconciled before charging';
  END IF;
  SELECT * INTO v_cycle FROM public.subscription_billing_cycles
  WHERE subscription_id = v_sub.id AND cycle_number = v_sub.billing_cycle_number FOR UPDATE;
  IF v_cycle.id IS NOT NULL THEN
    RETURN to_jsonb(v_cycle);
  END IF;
  IF v_sub.current_period_end > clock_timestamp() + INTERVAL '1 hour' THEN
    RAISE EXCEPTION 'Membership is already paid for this period';
  END IF;
  IF p_automatic AND (v_sub.auto_renew IS NOT TRUE OR
     v_sub.cancellation_requested_at IS NOT NULL OR v_sub.cancelled_at IS NOT NULL OR
     v_sub.status <> 'active') THEN
    RAISE EXCEPTION 'Automatic renewal is disabled';
  END IF;

  v_amount := v_sub.renewal_charge_cents;
  v_purpose := CASE WHEN v_sub.status = 'inactive' AND v_sub.billing_cycle_number = 0
    THEN 'subscription' ELSE 'subscription_renewal' END;
  IF p_promotion_id IS NOT NULL THEN
    IF p_automatic OR v_sub.billing_cycle_number <> 0 OR v_sub.status <> 'inactive' THEN
      RAISE EXCEPTION 'Introductory offer cannot replace an existing membership';
    END IF;
    SELECT p.initial_charge_cents, p.free_months, p.free_months IS NULL
      INTO v_amount, v_free_months, v_lifetime
    FROM public.promotions p JOIN public.promotion_participant_emails e ON e.promotion_id = p.id
    WHERE p.id = p_promotion_id AND e.id = p_participant_id
      AND lower(e.email) = lower(v_email) AND e.is_claimed IS NOT TRUE
      AND p.is_intro_campaign IS TRUE AND p.is_active IS TRUE
      AND (p.starts_at IS NULL OR p.starts_at <= now())
      AND (p.ends_at IS NULL OR p.ends_at > now())
    FOR UPDATE OF p, e;
    IF NOT FOUND THEN RAISE EXCEPTION 'Introductory offer is not available'; END IF;
    UPDATE public.subscriptions SET
      renewal_charge_cents = (SELECT renewal_charge_cents FROM public.promotions WHERE id = p_promotion_id)
    WHERE id = v_sub.id;
    v_purpose := 'promotion_intro';
  END IF;
  IF v_amount IS NULL OR v_amount <= 0 THEN RAISE EXCEPTION 'Invalid subscription amount'; END IF;
  INSERT INTO public.subscription_billing_cycles(
    id, subscription_id, user_id, cycle_number, reference, amount_cents, purpose,
    free_months, lifetime, promotion_id, participant_id)
  VALUES (v_id, v_sub.id, p_user_id, v_sub.billing_cycle_number,
    'll-sub-' || v_id::text, v_amount, v_purpose,
    v_free_months, v_lifetime, p_promotion_id, p_participant_id)
  RETURNING * INTO v_cycle;
  RETURN to_jsonb(v_cycle);
END;
$$;

CREATE FUNCTION public.claim_subscription_billing(p_cycle_id uuid, p_automatic boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_sub public.subscriptions%ROWTYPE;
  v_cycle public.subscription_billing_cycles%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
  SELECT s.* INTO STRICT v_sub FROM public.subscriptions s
  JOIN public.subscription_billing_cycles c ON c.subscription_id = s.id
  WHERE c.id = p_cycle_id FOR UPDATE OF s;
  SELECT * INTO STRICT v_cycle FROM public.subscription_billing_cycles WHERE id = p_cycle_id FOR UPDATE;
  IF v_sub.billing_owner <> 'server' OR NULLIF(BTRIM(v_sub.paystack_subscription_code), '') IS NOT NULL
     OR v_sub.billing_cycle_number <> v_cycle.cycle_number
     OR v_cycle.state <> 'ready'
     OR v_sub.current_period_end > clock_timestamp() + INTERVAL '1 hour'
     OR (p_automatic AND (v_sub.auto_renew IS NOT TRUE OR v_sub.status <> 'active'
        OR v_sub.cancellation_requested_at IS NOT NULL OR v_sub.cancelled_at IS NOT NULL)) THEN
    INSERT INTO public.subscription_billing_audit(cycle_id, subscription_id, action)
    VALUES (v_cycle.id, v_sub.id, 'submission_blocked');
    RETURN false;
  END IF;
  IF NOT p_automatic THEN
    UPDATE public.subscriptions SET auto_renew = true,
      cancellation_requested_at = NULL, cancelled_at = NULL WHERE id = v_sub.id;
  END IF;
  UPDATE public.subscription_billing_cycles SET state = 'submitting',
    submitted_at = clock_timestamp(), updated_at = clock_timestamp() WHERE id = v_cycle.id;
  INSERT INTO public.subscription_billing_audit(cycle_id, subscription_id, action)
  VALUES (v_cycle.id, v_sub.id, 'submission_started');
  RETURN true;
END;
$$;

CREATE FUNCTION public.record_subscription_billing_outcome(
  p_reference text, p_state text, p_detail text DEFAULT NULL, p_authorization_url text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cycle public.subscription_billing_cycles%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
  IF p_state NOT IN ('pending', 'unknown', 'failed') THEN RAISE EXCEPTION 'Invalid billing outcome'; END IF;
  SELECT * INTO STRICT v_cycle FROM public.subscription_billing_cycles WHERE reference = p_reference FOR UPDATE;
  IF v_cycle.state IN ('submitting', 'pending', 'unknown') THEN
    UPDATE public.subscription_billing_cycles SET state = p_state,
      failure_reason = p_detail, authorization_url = COALESCE(p_authorization_url, authorization_url),
      updated_at = clock_timestamp() WHERE id = v_cycle.id;
  END IF;
  INSERT INTO public.subscription_billing_audit(cycle_id, subscription_id, action, detail)
  VALUES (v_cycle.id, v_cycle.subscription_id, 'outcome_' || p_state, p_detail);
END;
$$;

-- A fresh reference is allowed only after server verification of a terminal failure.
-- Unknown, pending, abandoned and reversed attempts cannot enter this path.
CREATE FUNCTION public.retry_subscription_billing(
  p_cycle_id uuid, p_failed_reference text, p_transaction_id text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cycle public.subscription_billing_cycles%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
  SELECT * INTO STRICT v_cycle FROM public.subscription_billing_cycles WHERE id = p_cycle_id FOR UPDATE;
  IF v_cycle.state <> 'failed' OR v_cycle.reference <> p_failed_reference
     OR NULLIF(BTRIM(p_transaction_id), '') IS NULL THEN
    RETURN to_jsonb(v_cycle);
  END IF;
  INSERT INTO public.subscription_billing_failed_attempts(reference, cycle_id, provider_transaction_id)
  VALUES (v_cycle.reference, v_cycle.id, p_transaction_id);
  UPDATE public.subscription_billing_cycles SET reference = 'll-sub-' || gen_random_uuid()::text,
    state = 'ready', submitted_at = NULL, authorization_url = NULL, failure_reason = NULL,
    updated_at = clock_timestamp() WHERE id = v_cycle.id RETURNING * INTO v_cycle;
  INSERT INTO public.subscription_billing_audit(cycle_id, subscription_id, action, detail)
  VALUES (v_cycle.id, v_cycle.subscription_id, 'verified_failure_retry', p_failed_reference);
  RETURN to_jsonb(v_cycle);
END;
$$;

CREATE FUNCTION public.finalise_subscription_billing(
  p_reference text, p_transaction_id text, p_amount_cents integer, p_currency text,
  p_user_id uuid, p_paid_at timestamptz, p_authorization jsonb DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cycle public.subscription_billing_cycles%ROWTYPE;
  v_sub public.subscriptions%ROWTYPE;
  v_start timestamptz;
  v_end timestamptz;
  v_profile_deactivated boolean;
  v_preserve_deactivation boolean;
  v_card_count integer;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
  SELECT is_deactivated INTO v_profile_deactivated FROM public.profiles WHERE id = (
    SELECT user_id FROM public.subscription_billing_cycles WHERE reference = p_reference
  ) FOR UPDATE;
  SELECT s.* INTO STRICT v_sub FROM public.subscriptions s
  JOIN public.subscription_billing_cycles c ON c.subscription_id = s.id
  WHERE c.reference = p_reference FOR UPDATE OF s;
  SELECT * INTO STRICT v_cycle FROM public.subscription_billing_cycles WHERE reference = p_reference FOR UPDATE;
  IF p_user_id IS DISTINCT FROM v_cycle.user_id OR p_amount_cents IS DISTINCT FROM v_cycle.amount_cents
    OR p_currency IS DISTINCT FROM v_cycle.currency OR NULLIF(BTRIM(p_transaction_id), '') IS NULL
    OR p_paid_at IS NULL THEN RAISE EXCEPTION 'Payment does not match billing obligation'; END IF;
  IF v_cycle.state = 'paid' THEN
    IF v_cycle.provider_transaction_id <> p_transaction_id THEN RAISE EXCEPTION 'Conflicting provider transaction'; END IF;
    RETURN jsonb_build_object('applied', false, 'state', 'paid', 'user_id', v_cycle.user_id);
  END IF;
  IF v_cycle.submitted_at IS NULL OR v_cycle.cycle_number <> v_sub.billing_cycle_number THEN
    RAISE EXCEPTION 'Unsubmitted or superseded billing obligation requires review';
  END IF;
  v_preserve_deactivation := v_profile_deactivated IS TRUE AND
    (v_sub.cancellation_requested_at IS NOT NULL OR v_sub.cancelled_at IS NOT NULL);
  v_start := GREATEST(v_sub.current_period_end, p_paid_at);
  v_end := CASE WHEN v_cycle.lifetime THEN v_start + INTERVAL '100 years'
    WHEN v_cycle.purpose = 'promotion_intro' THEN v_start + make_interval(months => GREATEST(COALESCE(v_cycle.free_months, 1), 1))
    WHEN v_sub.billing_interval = 'calendar_month' THEN v_start + INTERVAL '1 month'
    ELSE v_start + INTERVAL '30 days' END;

  IF p_authorization->>'reusable' = 'true'
     AND NULLIF(p_authorization->>'authorization_code', '') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.members_card_details WHERE user_id = v_cycle.user_id
       AND authorization_code = p_authorization->>'authorization_code') THEN
    SELECT count(*) INTO v_card_count FROM public.members_card_details
    WHERE user_id = v_cycle.user_id AND is_active = true;
    IF v_card_count < 3 THEN
      INSERT INTO public.members_card_details(user_id, authorization_code, card_type, last4,
        exp_month, exp_year, bank, brand, is_active, is_primary)
      VALUES (v_cycle.user_id, p_authorization->>'authorization_code',
        COALESCE(p_authorization->>'card_type', 'card'), COALESCE(p_authorization->>'last4', '****'),
        NULLIF(p_authorization->>'exp_month', '')::integer, NULLIF(p_authorization->>'exp_year', '')::integer,
        p_authorization->>'bank', p_authorization->>'brand', true, v_card_count = 0);
    ELSE
      INSERT INTO public.subscription_billing_audit(cycle_id, subscription_id, action)
      VALUES (v_cycle.id, v_sub.id, 'card_not_saved_at_limit');
    END IF;
  END IF;

  UPDATE public.subscription_billing_cycles SET state = 'paid',
    provider_transaction_id = p_transaction_id, paid_at = p_paid_at, updated_at = clock_timestamp()
  WHERE id = v_cycle.id;
  UPDATE public.subscriptions SET status = CASE WHEN v_preserve_deactivation THEN 'inactive' ELSE 'active' END,
    current_period_start = v_start, current_period_end = v_end,
    billing_cycle_number = billing_cycle_number + 1,
    auto_renew = CASE WHEN v_cycle.lifetime THEN false ELSE auto_renew END,
    plan_type = CASE WHEN v_cycle.purpose = 'promotion_intro' THEN 'promotion_intro' ELSE plan_type END,
    promotion_id = COALESCE(v_cycle.promotion_id, promotion_id),
    promo_participant_id = COALESCE(v_cycle.participant_id, promo_participant_id),
    initial_charge_cents = CASE WHEN v_cycle.purpose = 'promotion_intro' THEN v_cycle.amount_cents ELSE initial_charge_cents END,
    intro_charge_reference = CASE WHEN v_cycle.purpose = 'promotion_intro' THEN p_reference ELSE intro_charge_reference END,
    intro_charge_paid_at = CASE WHEN v_cycle.purpose = 'promotion_intro' THEN p_paid_at ELSE intro_charge_paid_at END,
    free_period_end = CASE WHEN v_cycle.purpose = 'promotion_intro' THEN v_end ELSE free_period_end END,
    renewal_in_progress_at = NULL, updated_at = clock_timestamp()
  WHERE id = v_sub.id;
  UPDATE public.profiles SET subscription = CASE WHEN v_preserve_deactivation THEN 'inactive' ELSE 'active' END,
    is_deactivated = CASE WHEN v_preserve_deactivation THEN is_deactivated ELSE false END,
    deactivation_reason = CASE WHEN v_preserve_deactivation THEN deactivation_reason ELSE NULL END,
    deactivated_at = CASE WHEN v_preserve_deactivation THEN deactivated_at ELSE NULL END, updated_at = clock_timestamp()
  WHERE id = v_cycle.user_id;
  IF NOT v_preserve_deactivation THEN
    PERFORM public.ensure_member_qr_matches_subscription(v_cycle.user_id, v_end);
  END IF;
  IF v_cycle.participant_id IS NOT NULL THEN
    UPDATE public.promotion_participant_emails SET is_claimed = true,
      claimed_by = v_cycle.user_id, claimed_at = p_paid_at WHERE id = v_cycle.participant_id;
  END IF;
  INSERT INTO public.subscription_renewals(subscription_id, user_id, renewal_date, amount, status, payment_method, qr_code_updated)
  VALUES (v_sub.id, v_cycle.user_id, p_paid_at, v_cycle.amount_cents / 100.0, 'success', p_reference, true);
  INSERT INTO public.notifications(user_id, title, message, type, is_read, data)
  VALUES (v_cycle.user_id, 'Membership Payment Confirmed',
    'Your membership payment has been confirmed.', 'subscription_renewal', false,
    jsonb_build_object('reference', p_reference, 'amount', v_cycle.amount_cents / 100.0, 'expires_at', v_end));
  INSERT INTO public.subscription_billing_audit(cycle_id, subscription_id, action)
  VALUES (v_cycle.id, v_sub.id, 'payment_applied');
  RETURN jsonb_build_object('applied', true, 'state', 'paid', 'user_id', v_cycle.user_id, 'current_period_end', v_end);
END;
$$;

CREATE FUNCTION public.expire_server_subscription_access(p_user_id uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_sub record;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
  FOR v_sub IN
    SELECT id, user_id FROM public.subscriptions
    WHERE billing_owner = 'server' AND status IN ('active', 'cancelled')
      AND current_period_end < clock_timestamp() - INTERVAL '36 hours'
      AND (p_user_id IS NULL OR user_id = p_user_id)
    ORDER BY user_id, id
  LOOP
    -- Match finalisation's profile-first lock order and recheck after waiting.
    PERFORM 1 FROM public.profiles WHERE id = v_sub.user_id FOR UPDATE;
    UPDATE public.subscriptions SET status = 'expired', updated_at = clock_timestamp()
    WHERE id = v_sub.id AND billing_owner = 'server' AND status IN ('active', 'cancelled')
      AND current_period_end < clock_timestamp() - INTERVAL '36 hours';
    IF NOT FOUND THEN CONTINUE; END IF;
    UPDATE public.profiles SET subscription = 'expired', updated_at = clock_timestamp()
    WHERE id = v_sub.user_id;
    UPDATE public.user_qr_codes SET is_active = false WHERE user_id = v_sub.user_id AND is_active;
    INSERT INTO public.notifications(user_id, title, message, type, is_read, data)
    VALUES (v_sub.user_id, 'Membership Payment Required',
      'Your paid membership has ended. Check your payment status before making another payment.',
      'payment_failure', false, jsonb_build_object('subscription_id', v_sub.id));
  END LOOP;
END;
$$;

-- Retire the legacy app/worker charging claim. Only the ledger may submit subscription debits.
CREATE OR REPLACE FUNCTION public.claim_subscription_renewal(p_subscription_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN false;
END;
$$;

CREATE OR REPLACE VIEW public.subscriptions_due_for_renewal AS
SELECT s.id AS subscription_id, s.user_id, s.plan_type, s.renewal_charge_cents,
  s.current_period_end, s.auto_renew, p.email, p.paystack_customer_code,
  mcd.authorization_code, mcd.card_type, mcd.last4, p.email AS card_email,
  s.paystack_subscription_code
FROM public.subscriptions s
JOIN public.profiles p ON p.id = s.user_id
LEFT JOIN public.members_card_details mcd ON mcd.user_id = s.user_id
  AND mcd.is_primary = true AND mcd.is_active = true
WHERE s.billing_owner = 'server' AND s.status = 'active' AND s.auto_renew IS TRUE
  AND s.cancellation_requested_at IS NULL AND s.cancelled_at IS NULL
  AND NULLIF(BTRIM(s.paystack_subscription_code), '') IS NULL
  AND s.current_period_end <= now() + INTERVAL '1 hour';

-- Old clients may request cancellation, but cannot create or extend paid membership.
CREATE FUNCTION public.guard_subscription_billing_writes()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  -- Preserve trusted SECURITY DEFINER business operations such as admin promotion grants.
  IF auth.role() = 'service_role' OR current_user IN ('postgres', 'supabase_admin') THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN RAISE EXCEPTION 'Subscription activation requires verified server billing'; END IF;
  IF (to_jsonb(NEW) - ARRAY['status','auto_renew','cancellation_requested_at','cancelled_at','updated_at','renewal_in_progress_at'])
    IS DISTINCT FROM
    (to_jsonb(OLD) - ARRAY['status','auto_renew','cancellation_requested_at','cancelled_at','updated_at','renewal_in_progress_at'])
    OR (NEW.auto_renew IS TRUE AND OLD.auto_renew IS NOT TRUE)
    OR (NEW.status IS DISTINCT FROM OLD.status AND
      (NEW.status NOT IN ('cancelled', 'inactive') OR NEW.auto_renew IS NOT FALSE)) THEN
    RAISE EXCEPTION 'Subscription billing fields are server managed';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER guard_subscription_billing_writes BEFORE INSERT OR UPDATE ON public.subscriptions
FOR EACH ROW EXECUTE FUNCTION public.guard_subscription_billing_writes();

REVOKE ALL ON FUNCTION public.enable_server_subscription_billing(uuid,text,text),
  public.prepare_subscription_billing(uuid,boolean,uuid,uuid),
  public.claim_subscription_billing(uuid,boolean),
  public.record_subscription_billing_outcome(text,text,text,text),
  public.retry_subscription_billing(uuid,text,text),
  public.expire_server_subscription_access(uuid),
  public.finalise_subscription_billing(text,text,integer,text,uuid,timestamptz,jsonb)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enable_server_subscription_billing(uuid,text,text),
  public.prepare_subscription_billing(uuid,boolean,uuid,uuid),
  public.claim_subscription_billing(uuid,boolean),
  public.record_subscription_billing_outcome(text,text,text,text),
  public.retry_subscription_billing(uuid,text,text),
  public.expire_server_subscription_access(uuid),
  public.finalise_subscription_billing(text,text,integer,text,uuid,timestamptz,jsonb)
TO service_role;

COMMIT;
