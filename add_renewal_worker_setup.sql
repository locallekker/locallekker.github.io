-- ============================================================
-- Renewal Worker Setup
-- Run ONCE in Supabase SQL Editor (staging first, then prod).
-- ============================================================

-- ── 1. View: subscriptions due for auto-renewal ──────────────
-- Used by the Edge Function to find members to charge today.
CREATE OR REPLACE VIEW public.subscriptions_due_for_renewal AS
SELECT
  s.id                     AS subscription_id,
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
  p.email                  AS card_email,
  s.paystack_subscription_code
FROM public.subscriptions s
JOIN public.profiles p ON p.id = s.user_id
LEFT JOIN public.members_card_details mcd
  ON mcd.user_id = s.user_id AND mcd.is_primary = true AND mcd.is_active = true
WHERE
  s.status = 'active'
  AND s.auto_renew = true
  -- If Paystack recurring subscriptions are active, Paystack itself will
  -- perform the monthly charge and emit subscription.charge webhooks.
  -- Exclude those rows to avoid a second local charge_authorization debit.
  AND COALESCE(NULLIF(s.paystack_subscription_code, ''), NULL) IS NULL
  AND s.current_period_end <= now() + INTERVAL '1 hour'
  -- Idempotency: no successful renewal logged for this billing cycle yet
  AND NOT EXISTS (
    SELECT 1
    FROM public.subscription_renewals sr
    WHERE sr.user_id = s.user_id
      AND sr.status = 'success'
      AND sr.renewal_date >= s.current_period_end - INTERVAL '1 hour'
      AND sr.renewal_date <= s.current_period_end + INTERVAL '25 hours'
  );

-- ── 2. Add auto_renew column to subscriptions (if not present) ──
-- This column was introduced in add_intro_campaign_promotions.sql.
-- Adding here as a safety net in case that migration hasn't run yet.
ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS auto_renew BOOLEAN DEFAULT false;

-- ── 3. subscription_renewals already has all required columns ───
-- Existing schema: id, subscription_id, user_id, renewal_date, amount,
-- status CHECK ('success','failed','pending'), payment_method, qr_code_updated,
-- error_message, created_at
-- No schema changes needed — the view-based idempotency check handles everything.

-- ── 4. pg_net + pg_cron: daily cron job calling the Edge Function ──
-- Prerequisites: pg_cron and pg_net extensions must be enabled in Supabase.
-- Enable via: Dashboard → Database → Extensions → search "pg_cron" & "pg_net"
--
-- Replace <PROJECT_REF> with your Supabase project ref (e.g. qdrotavcmmevhgveodcp).
-- Replace <CRON_SECRET>  with a random secret you set in Edge Function env vars
--                        (Dashboard → Edge Functions → scheduled-renewal-worker → Secrets).
--
-- Run this block separately after enabling the extensions:

/*
SELECT cron.schedule(
  'daily-subscription-renewal',  -- job name (unique)
  '0 3 * * *',                   -- every day at 03:00 UTC
  $$
    SELECT net.http_post(
      url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/scheduled-renewal-worker',
      headers := jsonb_build_object(
                   'Content-Type',  'application/json',
                   'x-cron-secret', '<CRON_SECRET>'
                 ),
      body    := '{}'::jsonb
    );
  $$
);
*/

-- To remove the job later:
-- SELECT cron.unschedule('daily-subscription-renewal');

-- ── 5. RLS: service_role can update subscriptions (already unrestricted) ──
-- Nothing extra needed — service_role bypasses RLS by default.
