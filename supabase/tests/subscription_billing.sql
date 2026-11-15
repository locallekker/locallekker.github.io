-- Disposable database only. No provider requests are made.
BEGIN;
SELECT '1..2' AS tap;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
INSERT INTO auth.users(id, email, raw_user_meta_data)
VALUES ('bc100000-0000-0000-0000-000000000001', 'billing-fixture@example.test', '{"role":"member"}');
INSERT INTO public.profiles(id, email, name, surname, role)
VALUES ('bc100000-0000-0000-0000-000000000001', 'billing-fixture@example.test', 'Billing', 'Fixture', 'member')
ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;

DO $$
DECLARE
  v_user uuid := 'bc100000-0000-0000-0000-000000000001';
  v_sub uuid;
  v_cycle jsonb;
  v_other jsonb;
  v_end timestamptz;
  v_result jsonb;
BEGIN
  INSERT INTO public.subscriptions(user_id, plan_type, status, auto_renew,
    current_period_start, current_period_end, renewal_charge_cents)
  VALUES (v_user, 'subscription', 'active', true, now() - INTERVAL '30 days', now(), 9900)
  RETURNING id INTO v_sub;
  IF (SELECT billing_owner FROM public.subscriptions WHERE id = v_sub) <> 'migration_pending' THEN
    RAISE EXCEPTION 'Existing subscriptions must not default to server charging';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.subscriptions_due_for_renewal WHERE subscription_id = v_sub)
     OR EXISTS (SELECT 1 FROM public.server_subscriptions_due_for_renewal WHERE subscription_id = v_sub) THEN
    RAISE EXCEPTION 'Legacy membership was not kept in its original renewal cohort';
  END IF;
  IF NOT public.claim_subscription_renewal(v_sub) THEN
    RAISE EXCEPTION 'Staged rollout disabled an existing legacy renewal';
  END IF;
  IF public.claim_subscription_renewal(v_sub) THEN
    RAISE EXCEPTION 'Legacy renewal was claimed twice';
  END IF;
  PERFORM public.release_subscription_renewal_claim(v_sub);
  UPDATE public.subscriptions SET billing_owner = 'paystack' WHERE id = v_sub;
  IF public.claim_subscription_renewal(v_sub)
     OR EXISTS (SELECT 1 FROM public.subscriptions_due_for_renewal WHERE subscription_id = v_sub) THEN
    RAISE EXCEPTION 'Provider-owned membership also allowed a legacy debit';
  END IF;
  UPDATE public.subscriptions SET billing_owner = 'migration_pending' WHERE id = v_sub;
  BEGIN
    PERFORM public.prepare_subscription_billing(v_user, true);
    RAISE EXCEPTION 'Missing ownership allowed a charge';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'billing_migration_required:%' THEN RAISE; END IF;
  END;
  PERFORM public.enable_server_subscription_billing(v_sub, 'Sandbox: no active provider subscriptions; no unresolved charges', '30_days');
  IF public.claim_subscription_renewal(v_sub)
     OR EXISTS (SELECT 1 FROM public.subscriptions_due_for_renewal WHERE subscription_id = v_sub)
     OR NOT EXISTS (SELECT 1 FROM public.server_subscriptions_due_for_renewal WHERE subscription_id = v_sub) THEN
    RAISE EXCEPTION 'Server-owned membership was not isolated from legacy renewals';
  END IF;
  v_cycle := public.prepare_subscription_billing(v_user, true);
  IF (v_cycle->>'amount_cents')::integer <> 9900 THEN RAISE EXCEPTION 'Incorrect renewal amount'; END IF;
  IF NOT public.claim_subscription_billing((v_cycle->>'id')::uuid, true) THEN RAISE EXCEPTION 'First claim failed'; END IF;
  IF public.claim_subscription_billing((v_cycle->>'id')::uuid, false) THEN RAISE EXCEPTION 'Duplicate claim succeeded'; END IF;
  PERFORM public.record_subscription_billing_outcome(v_cycle->>'reference', 'unknown', 'Simulated timeout');
  BEGIN
    DELETE FROM public.subscriptions WHERE id = v_sub;
    RAISE EXCEPTION 'Unresolved payment history could be deleted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Reconcile the in-flight membership payment before deleting this account' THEN RAISE; END IF;
  END;
  UPDATE public.subscriptions SET current_period_end = now() - INTERVAL '2 minutes' WHERE id = v_sub;
  v_other := public.prepare_subscription_billing(v_user, false);
  IF v_other->>'id' <> v_cycle->>'id' THEN RAISE EXCEPTION 'Date edit created another obligation'; END IF;
  IF public.claim_subscription_billing((v_cycle->>'id')::uuid, true) THEN RAISE EXCEPTION 'Unknown payment was resubmitted'; END IF;
  BEGIN
    PERFORM public.finalise_subscription_billing(v_cycle->>'reference', 'fixture-transaction', 100, 'ZAR', v_user, now());
    RAISE EXCEPTION 'Incorrect amount was applied';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Payment does not match billing obligation' THEN RAISE; END IF;
  END;
  -- Cancellation during submission must survive payment finalisation.
  UPDATE public.subscriptions SET auto_renew = false, cancellation_requested_at = now() WHERE id = v_sub;
  v_result := public.finalise_subscription_billing(v_cycle->>'reference', 'fixture-transaction', 9900, 'ZAR', v_user, now(),
    '{"reusable":true,"authorization_code":"AUTH_billing_fixture","card_type":"visa","last4":"0000","exp_month":"12","exp_year":"2030"}');
  IF (v_result->>'applied')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'Payment was not applied'; END IF;
  SELECT current_period_end INTO v_end FROM public.subscriptions WHERE id = v_sub;
  v_result := public.finalise_subscription_billing(v_cycle->>'reference', 'fixture-transaction', 9900, 'ZAR', v_user, now());
  IF (v_result->>'applied')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'Payment applied twice'; END IF;
  IF (SELECT current_period_end FROM public.subscriptions WHERE id = v_sub) <> v_end THEN RAISE EXCEPTION 'Replayed payment extended access'; END IF;
  IF (SELECT auto_renew FROM public.subscriptions WHERE id = v_sub) THEN RAISE EXCEPTION 'Payment undid cancellation'; END IF;
  IF (SELECT count(*) FROM public.members_card_details WHERE user_id = v_user
      AND authorization_code = 'AUTH_billing_fixture') <> 1 THEN
    RAISE EXCEPTION 'Reusable card was not saved once';
  END IF;
  IF (SELECT count(*) FROM public.subscription_renewals WHERE payment_method = v_cycle->>'reference') <> 1 THEN
    RAISE EXCEPTION 'Duplicate renewal history';
  END IF;
  IF (SELECT count(*) FROM public.notifications WHERE data->>'reference' = v_cycle->>'reference') <> 1 THEN
    RAISE EXCEPTION 'Duplicate membership notification';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.user_qr_codes WHERE user_id = v_user AND is_active AND expires_at = v_end) THEN
    RAISE EXCEPTION 'QR did not follow the paid membership';
  END IF;
  BEGIN
    PERFORM public.prepare_subscription_billing(v_user, false);
    RAISE EXCEPTION 'Paid period could be billed early';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Membership is already paid for this period' THEN RAISE; END IF;
  END;

  UPDATE public.subscriptions SET current_period_end = now(), auto_renew = true,
    cancellation_requested_at = NULL WHERE id = v_sub;
  v_other := public.prepare_subscription_billing(v_user, true);
  IF v_other->>'reference' = v_cycle->>'reference' THEN RAISE EXCEPTION 'New period reused a payment reference'; END IF;
  UPDATE public.subscriptions SET auto_renew = false, cancellation_requested_at = now() WHERE id = v_sub;
  IF public.claim_subscription_billing((v_other->>'id')::uuid, true) THEN RAISE EXCEPTION 'Cancelled member was charged'; END IF;
  UPDATE public.subscriptions SET auto_renew = true, cancellation_requested_at = NULL WHERE id = v_sub;
  IF NOT public.claim_subscription_billing((v_other->>'id')::uuid, true) THEN RAISE EXCEPTION 'Next cycle claim failed'; END IF;
  PERFORM public.record_subscription_billing_outcome(v_other->>'reference', 'failed', 'Verified provider decline');
  v_result := public.retry_subscription_billing((v_other->>'id')::uuid, v_other->>'reference', 'fixture-declined-transaction');
  IF v_result->>'state' <> 'ready' OR v_result->>'reference' = v_other->>'reference' THEN
    RAISE EXCEPTION 'Verified failure retry did not retain the obligation with a new attempt';
  END IF;
  IF (SELECT count(*) FROM public.subscription_billing_failed_attempts WHERE reference = v_other->>'reference') <> 1 THEN
    RAISE EXCEPTION 'Failed attempt history was lost';
  END IF;
  IF NOT public.claim_subscription_billing((v_result->>'id')::uuid, false) THEN RAISE EXCEPTION 'Manual retry failed'; END IF;
  IF public.claim_subscription_billing((v_result->>'id')::uuid, false) THEN RAISE EXCEPTION 'Manual retry duplicated'; END IF;
  UPDATE public.subscriptions SET status = 'inactive', auto_renew = false,
    cancellation_requested_at = now() WHERE id = v_sub;
  UPDATE public.profiles SET is_deactivated = true, deactivation_reason = 'Fixture deactivation' WHERE id = v_user;
  DELETE FROM public.user_qr_codes WHERE user_id = v_user;
  PERFORM public.finalise_subscription_billing(v_result->>'reference', 'fixture-late-payment', 9900, 'ZAR', v_user, now());
  IF (SELECT status FROM public.subscriptions WHERE id = v_sub) <> 'inactive' OR
     (SELECT is_deactivated FROM public.profiles WHERE id = v_user) IS NOT TRUE THEN
    RAISE EXCEPTION 'In-flight payment undid account deactivation';
  END IF;
  IF EXISTS(SELECT 1 FROM public.user_qr_codes WHERE user_id = v_user AND is_active) THEN
    RAISE EXCEPTION 'In-flight payment recreated a deactivated account QR';
  END IF;
  UPDATE public.profiles SET is_deactivated = false WHERE id = v_user;
  UPDATE public.subscriptions SET status = 'active',
    current_period_end = now() - INTERVAL '35 hours' WHERE id = v_sub;
  PERFORM public.expire_server_subscription_access(v_user);
  IF (SELECT status FROM public.subscriptions WHERE id = v_sub) <> 'active' THEN
    RAISE EXCEPTION 'Access expired before the renewal grace ended';
  END IF;
  UPDATE public.subscriptions SET current_period_end = now() - INTERVAL '37 hours' WHERE id = v_sub;
  PERFORM public.expire_server_subscription_access(v_user);
  PERFORM public.expire_server_subscription_access(v_user);
  IF (SELECT status FROM public.subscriptions WHERE id = v_sub) <> 'expired'
     OR (SELECT subscription FROM public.profiles WHERE id = v_user) <> 'expired'
     OR EXISTS(SELECT 1 FROM public.user_qr_codes WHERE user_id = v_user AND is_active) THEN
    RAISE EXCEPTION 'Expired membership retained access';
  END IF;
  IF (SELECT count(*) FROM public.notifications WHERE user_id = v_user
      AND title = 'Membership Payment Required') <> 1 THEN
    RAISE EXCEPTION 'Expiry notification was duplicated';
  END IF;
  IF public.claim_subscription_renewal(v_sub) THEN RAISE EXCEPTION 'Legacy claim still charges'; END IF;
  IF has_function_privilege('authenticated', 'public.claim_subscription_billing(uuid,boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Member can bypass billing server';
  END IF;
  IF has_table_privilege('authenticated', 'public.subscription_billing_cycles', 'UPDATE') THEN
    RAISE EXCEPTION 'Member can alter billing ledger';
  END IF;
  DELETE FROM public.subscriptions WHERE id = v_sub;
  IF EXISTS (SELECT 1 FROM public.subscription_billing_cycles WHERE subscription_id = v_sub) THEN
    RAISE EXCEPTION 'Settled member deletion left orphan billing cycles';
  END IF;
  RAISE NOTICE 'Subscription billing database regression checks passed';
END;
$$;
SELECT 'ok 1 - membership billing claims, recovery, cancellation and retries' AS tap;

INSERT INTO auth.users(id, email, raw_user_meta_data) VALUES
('bc100000-0000-0000-0000-000000000002', 'intro-billing-fixture@example.test', '{"role":"member"}'),
('bc100000-0000-0000-0000-000000000003', 'lifetime-billing-fixture@example.test', '{"role":"member"}');
INSERT INTO public.profiles(id, email, name, surname, role) VALUES
('bc100000-0000-0000-0000-000000000002', 'intro-billing-fixture@example.test', 'Intro', 'Fixture', 'member'),
('bc100000-0000-0000-0000-000000000003', 'lifetime-billing-fixture@example.test', 'Lifetime', 'Fixture', 'member')
ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;

DO $$
DECLARE
  v_user uuid;
  v_promo uuid;
  v_participant uuid;
  v_cycle jsonb;
  v_sub public.subscriptions%ROWTYPE;
  v_lifetime boolean;
BEGIN
  FOREACH v_lifetime IN ARRAY ARRAY[false, true] LOOP
    v_user := CASE WHEN v_lifetime THEN 'bc100000-0000-0000-0000-000000000003'::uuid
      ELSE 'bc100000-0000-0000-0000-000000000002'::uuid END;
    v_promo := gen_random_uuid();
    v_participant := gen_random_uuid();
    INSERT INTO public.promotions(id, name, initial_charge_cents, renewal_charge_cents,
      free_months, is_intro_campaign, is_active)
    VALUES (v_promo, 'Billing offer fixture', 100, 9900,
      CASE WHEN v_lifetime THEN NULL ELSE 2 END, true, true);
    INSERT INTO public.promotion_participant_emails(id, promotion_id, email, is_claimed)
    SELECT v_participant, v_promo, email, false FROM public.profiles WHERE id = v_user;
    v_cycle := public.prepare_subscription_billing(v_user, false, v_promo, v_participant);
    IF v_cycle->>'purpose' <> 'promotion_intro' OR (v_cycle->>'amount_cents')::integer <> 100 THEN
      RAISE EXCEPTION 'Intro pricing is not authoritative';
    END IF;
    IF NOT public.claim_subscription_billing((v_cycle->>'id')::uuid, false) THEN RAISE EXCEPTION 'Intro claim failed'; END IF;
    PERFORM public.finalise_subscription_billing(v_cycle->>'reference', v_cycle->>'id', 100, 'ZAR', v_user, now());
    SELECT * INTO STRICT v_sub FROM public.subscriptions WHERE user_id = v_user;
    IF v_sub.auto_renew IS DISTINCT FROM NOT v_lifetime THEN RAISE EXCEPTION 'Incorrect lifetime renewal setting'; END IF;
    IF NOT v_lifetime AND v_sub.current_period_end < now() + INTERVAL '59 days' THEN
      RAISE EXCEPTION 'Free period was shortened';
    END IF;
    IF v_lifetime AND v_sub.current_period_end < now() + INTERVAL '99 years' THEN
      RAISE EXCEPTION 'Lifetime membership was shortened';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.promotion_participant_emails WHERE id = v_participant AND is_claimed) THEN
      RAISE EXCEPTION 'Intro claim was not committed with payment';
    END IF;
    BEGIN
      PERFORM public.prepare_subscription_billing(v_user, true);
      RAISE EXCEPTION 'Free or lifetime period was billed early';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'Membership is already paid for this period' THEN RAISE; END IF;
    END;
  END LOOP;
  RAISE NOTICE 'Introductory and lifetime billing regression checks passed';
END;
$$;
SELECT 'ok 2 - introductory periods and lifetime memberships' AS tap;
ROLLBACK;
