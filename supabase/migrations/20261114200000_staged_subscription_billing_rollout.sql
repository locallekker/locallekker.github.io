BEGIN;

CREATE VIEW public.server_subscriptions_due_for_renewal AS
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

REVOKE ALL ON public.server_subscriptions_due_for_renewal FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.server_subscriptions_due_for_renewal TO service_role;

-- Keep the deployed legacy worker on its original cohort until each member is reconciled.
CREATE OR REPLACE VIEW public.subscriptions_due_for_renewal AS
SELECT s.id AS subscription_id, s.user_id, s.plan_type, s.renewal_charge_cents,
  s.current_period_end, s.auto_renew, p.email, p.paystack_customer_code,
  mcd.authorization_code, mcd.card_type, mcd.last4, p.email AS card_email,
  s.paystack_subscription_code
FROM public.subscriptions s
JOIN public.profiles p ON p.id = s.user_id
LEFT JOIN public.members_card_details mcd ON mcd.user_id = s.user_id
  AND mcd.is_primary = true AND mcd.is_active = true
WHERE s.billing_owner = 'migration_pending' AND s.status = 'active' AND s.auto_renew IS TRUE
  AND NULLIF(BTRIM(s.paystack_subscription_code), '') IS NULL
  AND s.current_period_end <= now() + INTERVAL '1 hour'
  AND NOT EXISTS (
    SELECT 1 FROM public.subscription_renewals sr
    WHERE sr.user_id = s.user_id AND sr.status = 'success'
      AND sr.renewal_date >= s.current_period_end - INTERVAL '1 hour'
      AND sr.renewal_date <= s.current_period_end + INTERVAL '25 hours'
  );

CREATE OR REPLACE FUNCTION public.claim_subscription_renewal(p_subscription_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.subscriptions s
  SET renewal_in_progress_at = clock_timestamp(), updated_at = clock_timestamp()
  WHERE s.id = p_subscription_id
    AND s.billing_owner = 'migration_pending'
    AND NULLIF(BTRIM(s.paystack_subscription_code), '') IS NULL
    AND (s.user_id = auth.uid() OR auth.role() = 'service_role')
    AND s.status = 'active' AND s.auto_renew IS TRUE
    AND s.cancellation_requested_at IS NULL AND s.cancelled_at IS NULL
    AND s.current_period_end <= clock_timestamp() + INTERVAL '1 hour'
    AND (s.renewal_in_progress_at IS NULL
      OR s.renewal_in_progress_at < clock_timestamp() - INTERVAL '24 hours')
    AND NOT EXISTS (
      SELECT 1 FROM public.subscription_renewals sr
      WHERE sr.subscription_id = s.id AND sr.status = 'success'
        AND sr.renewal_date >= s.current_period_end - INTERVAL '1 hour'
        AND sr.renewal_date <= s.current_period_end + INTERVAL '25 hours'
    )
    AND (auth.role() = 'service_role' OR NOT EXISTS (
      SELECT 1 FROM public.subscription_renewals sr
      WHERE sr.subscription_id = s.id
        AND sr.payment_method = ('renewal_' || s.id::text || '_' ||
          floor(extract(epoch FROM s.current_period_end) * 1000)::bigint::text)
        AND sr.error_message ILIKE 'Duplicate Transaction Reference%'
    ));
  RETURN FOUND;
END;
$$;

DO $$
DECLARE
  v_job record;
  v_server_job bigint;
BEGIN
  IF to_regclass('cron.job') IS NULL THEN RETURN; END IF;
  SELECT schedule, command INTO v_job FROM cron.job
    WHERE jobname = 'daily-subscription-renewal';
  IF NOT FOUND THEN RETURN; END IF;
  IF v_job.command NOT LIKE '%/functions/v1/scheduled-renewal-worker%' THEN
    RAISE EXCEPTION 'Unexpected legacy renewal cron command; configure the server job explicitly';
  END IF;
  v_server_job := cron.schedule('server-subscription-renewal', v_job.schedule,
    replace(v_job.command, '/functions/v1/scheduled-renewal-worker',
      '/functions/v1/scheduled-server-renewal-worker'));
  PERFORM cron.alter_job(v_server_job, active := false);
END;
$$;

COMMIT;
