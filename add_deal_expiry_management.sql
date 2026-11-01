-- ============================================================
-- Trusted Partner Deal Expiry Management
-- Run ONCE in Supabase SQL Editor (staging first, then prod).
--
-- Purpose:
--   1. Auto-deactivate trusted_partner_discounts whose end_date has
--      passed so they disappear from member-facing listings.
--   2. Provide views the scheduled-deal-expiry-worker uses to find
--      deals expiring tomorrow and deals that expired today.
--   3. Provide idempotency storage so each (deal, notification_type)
--      is only emailed once.
-- ============================================================

BEGIN;

-- ── 1. Helper: extract end_date (DATE) from a deal row ──────────────
-- Reads schedule_data->>'end_date' (JSONB) first, then falls back to
-- the legacy `schedule_end_date` column if it exists. Returns NULL when
-- the deal has no expiry configured (open-ended deal).
CREATE OR REPLACE FUNCTION public.get_deal_end_date(
  p_schedule_data JSONB,
  p_schedule_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_end_text TEXT;
  v_end_date DATE;
BEGIN
  IF p_schedule_data IS NOT NULL THEN
    v_end_text := p_schedule_data->>'end_date';
    IF v_end_text IS NOT NULL AND length(v_end_text) > 0 THEN
      BEGIN
        v_end_date := (v_end_text)::date;
        RETURN v_end_date;
      EXCEPTION WHEN OTHERS THEN
        -- Fall through to legacy column
        NULL;
      END;
    END IF;
  END IF;

  IF p_schedule_end_date IS NOT NULL THEN
    RETURN p_schedule_end_date::date;
  END IF;

  RETURN NULL;
END;
$$;

-- ── 2. Idempotency table for expiry notifications ───────────────────
CREATE TABLE IF NOT EXISTS public.deal_expiry_notifications (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  deal_id          UUID NOT NULL REFERENCES public.trusted_partner_discounts(id) ON DELETE CASCADE,
  notification_type TEXT NOT NULL CHECK (notification_type IN ('expiring_tomorrow', 'expired')),
  recipient_role   TEXT NOT NULL CHECK (recipient_role IN ('trusted_partner', 'admin')),
  recipient_email  TEXT,
  sent_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  email_sent       BOOLEAN NOT NULL DEFAULT false,
  error_message    TEXT,
  UNIQUE (deal_id, notification_type, recipient_role)
);

CREATE INDEX IF NOT EXISTS idx_deal_expiry_notifications_deal
  ON public.deal_expiry_notifications(deal_id);
CREATE INDEX IF NOT EXISTS idx_deal_expiry_notifications_sent_at
  ON public.deal_expiry_notifications(sent_at DESC);

ALTER TABLE public.deal_expiry_notifications ENABLE ROW LEVEL SECURITY;

-- service_role bypasses RLS automatically; the worker uses the service key.
-- No policies needed for app users.

-- ── 3. Auto-expire deals whose end_date has passed ──────────────────
-- The scheduled worker calls this AFTER sending "expired" emails so we
-- still have the chance to email the partner before flipping the flag.
CREATE OR REPLACE FUNCTION public.expire_overdue_deals()
RETURNS TABLE (deal_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.trusted_partner_discounts d
  SET is_active = false,
      updated_at = now()
  WHERE d.is_active = true
    AND public.get_deal_end_date(d.schedule_data) IS NOT NULL
    AND public.get_deal_end_date(d.schedule_data) < (now() AT TIME ZONE 'UTC')::date
  RETURNING d.id;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_overdue_deals() FROM PUBLIC, anon, authenticated;

-- ── 4. View: deals expiring tomorrow (worker emails tp + admin) ─────
CREATE OR REPLACE VIEW public.tp_deals_expiring_tomorrow AS
SELECT
  d.id                        AS deal_id,
  d.name                      AS deal_name,
  d.trusted_partner_id        AS owner_user_id,
  d.business_id,
  d.deal_category,
  d.city,
  public.get_deal_end_date(d.schedule_data) AS end_date,
  b.name                      AS business_name,
  b.business_email            AS business_email,
  p.email                     AS owner_email,
  COALESCE(NULLIF(trim(concat(p.name, ' ', p.surname)), ''), 'Partner') AS owner_name
FROM public.trusted_partner_discounts d
LEFT JOIN public.businesses b ON b.id = d.business_id
LEFT JOIN public.profiles   p ON p.id = d.trusted_partner_id
WHERE d.is_active = true
  AND public.get_deal_end_date(d.schedule_data)
        = ((now() AT TIME ZONE 'UTC')::date + INTERVAL '1 day')::date;

-- ── 5. View: deals that have expired (end_date < today) and are still active ──
CREATE OR REPLACE VIEW public.tp_deals_expired_today AS
SELECT
  d.id                        AS deal_id,
  d.name                      AS deal_name,
  d.trusted_partner_id        AS owner_user_id,
  d.business_id,
  d.deal_category,
  d.city,
  public.get_deal_end_date(d.schedule_data) AS end_date,
  b.name                      AS business_name,
  b.business_email            AS business_email,
  p.email                     AS owner_email,
  COALESCE(NULLIF(trim(concat(p.name, ' ', p.surname)), ''), 'Partner') AS owner_name
FROM public.trusted_partner_discounts d
LEFT JOIN public.businesses b ON b.id = d.business_id
LEFT JOIN public.profiles   p ON p.id = d.trusted_partner_id
WHERE d.is_active = true
  AND public.get_deal_end_date(d.schedule_data) IS NOT NULL
  AND public.get_deal_end_date(d.schedule_data) < (now() AT TIME ZONE 'UTC')::date;

COMMIT;

-- ── 6. pg_cron schedule (run separately after enabling extensions) ──
-- Prerequisites: pg_cron + pg_net extensions enabled in Supabase.
-- Replace <PROJECT_REF> with your Supabase project ref (e.g. qdrotavcmmevhgveodcp).
-- Replace <CRON_SECRET> with the value of CRON_SECRET set on the
--   scheduled-deal-expiry-worker edge function.
--
-- Runs daily at 07:00 UTC (≈ 09:00 SAST) — early enough that the partner
-- has the whole business day to react.

/*
SELECT cron.schedule(
  'daily-deal-expiry-worker',
  '0 7 * * *',
  $$
    SELECT net.http_post(
      url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/scheduled-deal-expiry-worker',
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
-- SELECT cron.unschedule('daily-deal-expiry-worker');
