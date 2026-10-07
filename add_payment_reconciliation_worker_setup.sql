-- ============================================================
-- Payment Reconciliation Worker Setup
-- Run ONCE in Supabase SQL Editor (staging first, then prod).
--
-- Detects members who accepted terms and reached Paystack card entry
-- (paystack_customer_code set) but never ended up with an active
-- subscription — the same pattern found for carolgravett@gmail.com on
-- 2026-09-05. The scheduled-payment-reconciliation-worker edge function
-- checks each candidate against Paystack's own transaction history and
-- auto-activates confirmed successful payments, or flags ambiguous ones
-- for manual review. See /memories/repo/pending_activation_audit_2026-09.md.
-- ============================================================

-- ── 1. View: candidates for reconciliation ───────────────────
CREATE OR REPLACE VIEW public.pending_payment_reconciliation_candidates AS
SELECT
  p.id   AS user_id,
  p.email,
  p.name,
  p.surname,
  p.paystack_customer_code,
  p.created_at
FROM public.profiles p
WHERE p.role = 'member'
  AND coalesce(p.is_deactivated, false) = false
  AND coalesce(p.subscription, 'pending') <> 'active'
  AND p.paystack_customer_code IS NOT NULL
  AND p.member_terms_accepted = true
  -- Give the normal in-app flow (verify-on-return, background poll, webhook)
  -- a chance to self-heal first before this worker steps in.
  AND p.created_at <= now() - INTERVAL '30 minutes'
  AND NOT EXISTS (
    SELECT 1 FROM public.subscriptions s
    WHERE s.user_id = p.id AND s.status = 'active'
  );

-- ── 2. Audit log table ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payment_reconciliation_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.profiles(id),
  email text,
  action text NOT NULL, -- activated_subscription | activated_intro | flagged_review | no_payment_found | error
  paystack_reference text,
  detail text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.payment_reconciliation_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view reconciliation log" ON public.payment_reconciliation_log;
CREATE POLICY "Admins can view reconciliation log"
  ON public.payment_reconciliation_log
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );
-- No insert/update/delete policy needed: the edge function writes via the
-- service_role key, which bypasses RLS.

-- ── 3. pg_net + pg_cron: run every 30 minutes ────────────────
-- Prerequisites: pg_cron and pg_net extensions must be enabled in Supabase.
-- Enable via: Dashboard → Database → Extensions → search "pg_cron" & "pg_net"
--
-- Replace <PROJECT_REF> with your Supabase project ref (e.g. qdrotavcmmevhgveodcp).
-- Replace <CRON_SECRET>  with the SAME value already set for
--                        scheduled-renewal-worker (Edge Function secrets are
--                        shared project-wide, so no new secret is required).
--
-- Run this block separately after enabling the extensions:

/*
SELECT cron.schedule(
  'payment-reconciliation-worker',   -- job name (unique)
  '*/30 * * * *',                    -- every 30 minutes
  $$
    SELECT net.http_post(
      url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/scheduled-payment-reconciliation-worker',
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
-- SELECT cron.unschedule('payment-reconciliation-worker');
