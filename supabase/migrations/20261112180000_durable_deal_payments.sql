BEGIN;

ALTER TABLE public.deal_authorizations ADD COLUMN IF NOT EXISTS payment_reference text;

CREATE TABLE public.deal_payment_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  deal_id uuid NOT NULL REFERENCES public.deal_authorizations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reference text NOT NULL UNIQUE DEFAULT ('ll-deal-' || gen_random_uuid()::text),
  amount_cents integer NOT NULL CHECK (amount_cents > 0),
  currency text NOT NULL DEFAULT 'ZAR' CHECK (currency = 'ZAR'),
  subaccount_code text NOT NULL,
  state text NOT NULL DEFAULT 'ready'
    CHECK (state IN ('ready', 'submitting', 'pending', 'unknown', 'failed', 'paid')),
  authorization_url text,
  provider_transaction_id text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE UNIQUE INDEX one_unresolved_or_paid_attempt_per_deal
  ON public.deal_payment_attempts(deal_id) WHERE state <> 'failed';
ALTER TABLE public.deal_payment_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.deal_payment_attempts FROM anon, authenticated;
GRANT ALL ON public.deal_payment_attempts TO service_role;

CREATE FUNCTION public.guard_deal_payment_history()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF OLD.state IN ('submitting', 'pending', 'unknown') THEN
    RAISE EXCEPTION 'Reconcile the in-flight deal payment before deleting this account';
  END IF;
  RETURN OLD;
END;
$$;
CREATE TRIGGER guard_deal_payment_history BEFORE DELETE ON public.deal_payment_attempts
FOR EACH ROW EXECUTE FUNCTION public.guard_deal_payment_history();

CREATE FUNCTION public.guard_deal_payment_changes()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.role() = 'service_role' OR
    (auth.role() IS NULL AND current_user IN ('postgres', 'supabase_admin')) THEN RETURN NEW; END IF;
  IF (to_jsonb(NEW) - ARRAY['notes','updated_at']) IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['notes','updated_at'])
    AND EXISTS (SELECT 1 FROM public.deal_payment_attempts WHERE deal_id = OLD.id
      AND state IN ('submitting','pending','unknown','paid')) THEN
    RAISE EXCEPTION 'Deal payment is server managed; reconcile it before changing this deal';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER guard_deal_payment_changes BEFORE UPDATE ON public.deal_authorizations
FOR EACH ROW EXECUTE FUNCTION public.guard_deal_payment_changes();

CREATE FUNCTION public.prepare_deal_payment(p_user_id uuid, p_deal_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_deal public.deal_authorizations;
  v_payment public.deal_payment_attempts;
  v_profile public.profiles;
  v_bank public.trusted_partner_bank_accounts;
  v_business uuid;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
  SELECT * INTO STRICT v_deal FROM public.deal_authorizations WHERE id = p_deal_id FOR UPDATE;
  IF v_deal.member_id IS DISTINCT FROM p_user_id THEN RAISE EXCEPTION 'Deal does not belong to this member'; END IF;
  SELECT * INTO STRICT v_profile FROM public.profiles WHERE id = p_user_id;
  IF coalesce(v_profile.is_deactivated, false) THEN RAISE EXCEPTION 'Account is deactivated'; END IF;
  SELECT * INTO v_payment FROM public.deal_payment_attempts
    WHERE deal_id = p_deal_id ORDER BY created_at DESC, id DESC LIMIT 1;
  IF FOUND THEN
    RETURN to_jsonb(v_payment) || jsonb_build_object('email', v_profile.email, 'customer_code', v_profile.paystack_customer_code);
  END IF;
  IF v_deal.status IS NULL OR v_deal.status NOT IN ('approved', 'pending_payment') OR v_deal.payment_method IS DISTINCT FROM 'in_app'
     OR v_deal.payment_completed_at IS NOT NULL OR v_deal.amount IS NULL OR v_deal.amount <= 0 THEN
    RAISE EXCEPTION 'Deal is not available for in-app payment';
  END IF;
  v_business := v_deal.business_id;
  IF v_business IS NULL THEN
    SELECT business_id INTO v_business FROM public.trusted_partner_discounts WHERE id = v_deal.discount_id;
  END IF;
  SELECT a.* INTO STRICT v_bank FROM public.trusted_partner_bank_accounts a
    JOIN public.businesses b ON b.owner_member_id = a.user_id
    WHERE b.id = v_business AND a.is_active AND a.subaccount_active
      AND nullif(a.subaccount_code, '') IS NOT NULL;
  INSERT INTO public.deal_payment_attempts(deal_id, user_id, amount_cents, subaccount_code)
    VALUES (p_deal_id, p_user_id, round(v_deal.amount * 100)::integer, v_bank.subaccount_code)
    RETURNING * INTO v_payment;
  RETURN to_jsonb(v_payment) || jsonb_build_object('email', v_profile.email, 'customer_code', v_profile.paystack_customer_code);
END;
$$;

CREATE FUNCTION public.claim_deal_payment(p_payment_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_deal uuid;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
  SELECT deal_id INTO STRICT v_deal FROM public.deal_payment_attempts WHERE id = p_payment_id;
  PERFORM 1 FROM public.deal_authorizations WHERE id = v_deal FOR UPDATE;
  UPDATE public.deal_payment_attempts a SET state = 'submitting', updated_at = clock_timestamp()
    WHERE a.id = p_payment_id AND a.state = 'ready'
      AND EXISTS (SELECT 1 FROM public.deal_authorizations d JOIN public.profiles p ON p.id = d.member_id
        WHERE d.id = a.deal_id AND d.status IN ('approved', 'pending_payment') AND d.payment_method = 'in_app'
          AND d.payment_completed_at IS NULL AND round(d.amount * 100) = a.amount_cents
          AND NOT coalesce(p.is_deactivated, false));
  RETURN FOUND;
END;
$$;

CREATE FUNCTION public.record_deal_payment_outcome(p_reference text, p_state text, p_authorization_url text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
  IF p_state NOT IN ('pending', 'unknown', 'failed') THEN RAISE EXCEPTION 'Invalid payment outcome'; END IF;
  UPDATE public.deal_payment_attempts SET state = p_state,
    authorization_url = coalesce(p_authorization_url, authorization_url), updated_at = clock_timestamp()
    WHERE reference = p_reference AND state IN ('submitting', 'pending', 'unknown', 'failed');
END;
$$;

CREATE FUNCTION public.retry_deal_payment(p_payment_id uuid, p_reference text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_previous public.deal_payment_attempts;
  v_current public.deal_payment_attempts;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
  SELECT * INTO STRICT v_previous FROM public.deal_payment_attempts WHERE id = p_payment_id;
  PERFORM 1 FROM public.deal_authorizations WHERE id = v_previous.deal_id FOR UPDATE;
  SELECT * INTO STRICT v_previous FROM public.deal_payment_attempts WHERE id = p_payment_id FOR UPDATE;
  IF v_previous.state <> 'failed' OR v_previous.reference <> p_reference THEN
    RAISE EXCEPTION 'Verify the previous terminal failure before retrying';
  END IF;
  SELECT * INTO v_current FROM public.deal_payment_attempts WHERE deal_id = v_previous.deal_id
    AND state <> 'failed' ORDER BY created_at DESC LIMIT 1;
  IF NOT FOUND THEN
    INSERT INTO public.deal_payment_attempts(deal_id, user_id, amount_cents, subaccount_code)
      VALUES (v_previous.deal_id, v_previous.user_id, v_previous.amount_cents, v_previous.subaccount_code)
      RETURNING * INTO v_current;
  END IF;
  RETURN public.prepare_deal_payment(v_current.user_id, v_current.deal_id);
END;
$$;

CREATE FUNCTION public.finalise_deal_payment(p_deal_id uuid, p_user_id uuid, p_reference text,
  p_transaction_id text, p_amount_cents integer, p_currency text, p_paid_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_deal public.deal_authorizations;
  v_payment public.deal_payment_attempts;
  v_business public.businesses;
  v_profile public.profiles;
  v_receipt_number text;
  v_virtual uuid;
  v_paid_at timestamptz := coalesce(p_paid_at, clock_timestamp());
  v_deal_name text;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
  IF nullif(p_reference, '') IS NULL OR nullif(p_transaction_id, '') IS NULL THEN
    RAISE EXCEPTION 'Verified transaction identity is required';
  END IF;
  SELECT * INTO STRICT v_deal FROM public.deal_authorizations WHERE id = p_deal_id FOR UPDATE;
  IF v_deal.member_id IS DISTINCT FROM p_user_id OR p_currency IS DISTINCT FROM 'ZAR'
    OR p_amount_cents IS NULL OR p_amount_cents <= 0
    OR round(v_deal.amount * 100) IS DISTINCT FROM p_amount_cents::numeric THEN
    RAISE EXCEPTION 'Payment does not match this deal';
  END IF;
  IF v_deal.payment_method IS DISTINCT FROM 'in_app' OR v_deal.status IS NULL
     OR v_deal.status NOT IN ('approved', 'pending_payment', 'completed') THEN
    RAISE EXCEPTION 'Deal is not available for in-app payment';
  END IF;
  IF v_deal.payment_reference IS NOT NULL AND v_deal.payment_reference <> p_reference THEN
    RAISE EXCEPTION 'A different payment already completed this deal; reconcile before continuing';
  END IF;
  SELECT * INTO v_payment FROM public.deal_payment_attempts WHERE reference = p_reference FOR UPDATE;
  IF FOUND THEN
    IF v_payment.deal_id <> p_deal_id OR v_payment.user_id <> p_user_id OR v_payment.amount_cents <> p_amount_cents THEN
      RAISE EXCEPTION 'Payment does not match this deal';
    END IF;
    IF v_payment.state = 'ready' THEN
      RAISE EXCEPTION 'Payment has not been submitted';
    END IF;
    IF v_payment.state = 'paid' THEN
      IF v_payment.provider_transaction_id IS DISTINCT FROM p_transaction_id THEN
        RAISE EXCEPTION 'Conflicting provider transaction';
      END IF;
      RETURN jsonb_build_object('applied', false);
    END IF;
  ELSIF p_reference LIKE 'll-deal-%' THEN
    RAISE EXCEPTION 'Deal payment reference was not found';
  ELSIF EXISTS (SELECT 1 FROM public.deal_payment_attempts WHERE deal_id = p_deal_id AND state <> 'failed') THEN
    RAISE EXCEPTION 'An existing payment must be reconciled before applying a legacy charge';
  END IF;
  SELECT b.* INTO STRICT v_business FROM public.businesses b
    WHERE b.id = coalesce(v_deal.business_id,
      (SELECT business_id FROM public.trusted_partner_discounts WHERE id = v_deal.discount_id));
  SELECT * INTO STRICT v_profile FROM public.profiles WHERE id = p_user_id;
  SELECT coalesce(v_deal.deal_snapshot->>'name', name, 'Deal') INTO v_deal_name
    FROM public.trusted_partner_discounts WHERE id = v_deal.discount_id;
  IF v_payment.id IS NULL THEN
    INSERT INTO public.deal_payment_attempts(deal_id, user_id, reference, amount_cents, subaccount_code, state)
      VALUES (p_deal_id, p_user_id, p_reference, p_amount_cents, 'legacy_verified', 'pending')
      RETURNING * INTO v_payment;
  END IF;
  SELECT receipt_number INTO v_receipt_number FROM public.virtual_receipts
    WHERE deal_authorization_id = p_deal_id ORDER BY created_at LIMIT 1;
  IF v_receipt_number IS NULL THEN
    SELECT receipt_number INTO v_receipt_number FROM public.deal_receipts
      WHERE deal_authorization_id = p_deal_id ORDER BY created_at LIMIT 1;
  END IF;
  v_receipt_number := coalesce(v_receipt_number, 'RCP-' || p_deal_id::text);
  SELECT id INTO v_virtual FROM public.virtual_receipts WHERE deal_authorization_id = p_deal_id ORDER BY created_at LIMIT 1;
  IF v_virtual IS NULL THEN
    INSERT INTO public.virtual_receipts(deal_authorization_id, receipt_number, receipt_data, qr_code)
      VALUES (p_deal_id, v_receipt_number,
        jsonb_build_object('deal_authorization_id', p_deal_id, 'receipt_number', v_receipt_number,
          'business_name', v_business.name, 'business_id', v_business.id,
          'member_name', concat_ws(' ', v_profile.name, v_profile.surname), 'member_email', v_profile.email,
          'discount_name', v_deal_name, 'amount', v_deal.amount, 'payment_method', 'in_app',
          'transaction_date', v_paid_at, 'status', 'completed'),
        'RECEIPT:' || p_deal_id::text || ':' || v_receipt_number) RETURNING id INTO v_virtual;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.deal_receipts WHERE deal_authorization_id = p_deal_id) THEN
    INSERT INTO public.deal_receipts(deal_authorization_id, member_id, trusted_partner_id, business_id,
      receipt_number, amount, payment_method, business_name, discount_name, member_name, member_email)
    VALUES (p_deal_id, p_user_id, v_business.owner_member_id, v_business.id, v_receipt_number,
      v_deal.amount, 'in_app', v_business.name, v_deal_name,
      concat_ws(' ', v_profile.name, v_profile.surname), v_profile.email);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.member_receipts WHERE member_id = p_user_id AND virtual_receipt_id = v_virtual) THEN
    INSERT INTO public.member_receipts(member_id, virtual_receipt_id, receipt_type, title, amount, business_name, receipt_date)
      VALUES (p_user_id, v_virtual, 'virtual', v_receipt_number, v_deal.amount, v_business.name, v_paid_at);
  END IF;
  UPDATE public.deal_authorizations SET status = 'completed', payment_completed_at = v_paid_at,
    completed_at = coalesce(completed_at, v_paid_at), payment_reference = p_reference, updated_at = clock_timestamp()
    WHERE id = p_deal_id;
  UPDATE public.deal_payment_attempts SET state = 'paid', provider_transaction_id = p_transaction_id,
    updated_at = clock_timestamp() WHERE id = v_payment.id;
  UPDATE public.notifications SET is_read = true WHERE user_id = p_user_id AND NOT is_read
    AND type IN ('deal_approved', 'pos_deal_approved') AND data->>'deal_authorization_id' = p_deal_id::text;
  INSERT INTO public.notifications(user_id, title, message, type, is_read, data)
    VALUES (p_user_id, 'Payment Confirmed', 'Your payment and receipt have been confirmed.', 'payment_success', false,
      jsonb_build_object('reference', p_reference, 'deal_authorization_id', p_deal_id, 'receipt_number', v_receipt_number));
  RETURN jsonb_build_object('applied', true, 'receipt_number', v_receipt_number);
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_deal_payment(uuid,uuid),
  public.claim_deal_payment(uuid), public.record_deal_payment_outcome(text,text,text),
  public.retry_deal_payment(uuid,text), public.finalise_deal_payment(uuid,uuid,text,text,integer,text,timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_deal_payment(uuid,uuid),
  public.claim_deal_payment(uuid), public.record_deal_payment_outcome(text,text,text),
  public.retry_deal_payment(uuid,text), public.finalise_deal_payment(uuid,uuid,text,text,integer,text,timestamptz)
  TO service_role;

-- Preserve existing URLs and credentials while allowing the worker to return its result.
DO $$
DECLARE v_job record;
BEGIN
  IF to_regclass('cron.job') IS NULL THEN RETURN; END IF;
  FOR v_job IN SELECT jobid, command FROM cron.job
    WHERE jobname IN ('daily-subscription-renewal','payment-reconciliation-worker')
      AND command NOT ILIKE '%timeout_milliseconds%'
  LOOP
    PERFORM cron.alter_job(v_job.jobid, command := regexp_replace(v_job.command,
      'net[.]http_post\s*[(]', 'net.http_post(timeout_milliseconds := 120000, ', 'i'));
  END LOOP;
END;
$$;

COMMIT;
