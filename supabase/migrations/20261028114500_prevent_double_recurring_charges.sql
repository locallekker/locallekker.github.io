-- Prevent double-renewal debits when Paystack recurring subscriptions are enabled.
-- If paystack_subscription_code is present, Paystack performs the monthly charge;
-- local scheduled renewals must not also call charge_authorization.

BEGIN;

ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS paystack_subscription_code TEXT;

CREATE OR REPLACE VIEW public.subscriptions_due_for_renewal AS
SELECT
  s.id AS subscription_id,
  s.user_id,
  s.plan_type,
  s.renewal_charge_cents,
  s.current_period_end,
  s.auto_renew,
  p.email,
  p.paystack_customer_code,
  mcd.authorization_code,
  mcd.card_type,
  mcd.last4,
  p.email AS card_email,
  s.paystack_subscription_code
FROM public.subscriptions s
JOIN public.profiles p ON p.id = s.user_id
LEFT JOIN public.members_card_details mcd
  ON mcd.user_id = s.user_id
 AND mcd.is_primary = true
 AND mcd.is_active = true
WHERE s.status = 'active'
  AND s.auto_renew = true
  AND COALESCE(NULLIF(s.paystack_subscription_code, ''), NULL) IS NULL
  AND s.current_period_end <= now() + INTERVAL '1 hour'
  AND NOT EXISTS (
    SELECT 1
    FROM public.subscription_renewals sr
    WHERE sr.user_id = s.user_id
      AND sr.status = 'success'
      AND sr.renewal_date >= s.current_period_end - INTERVAL '1 hour'
      AND sr.renewal_date <= s.current_period_end + INTERVAL '25 hours'
  );

COMMIT;
