-- =============================================================================
-- Fix: intro-campaign (R1) members whose subscription was created ALREADY
-- EXPIRED because promotions.free_months IS NULL (lifetime) was coerced to 0
-- months, which set current_period_end = the signup instant.
--
-- Symptom: member signs up on an admin promotion, the R1 payment succeeds and
-- signup "works", but requesting a deal fails with
--   "You need an active subscription to request deals."
-- (deal_authorization_service.dart reads subscriptions.status = 'active').
--
-- Root cause is fixed in code (SubscriptionService.activateIntroCampaignSubscription
-- and paystack-webhook recoverIntroCampaignPayment now read the authoritative
-- promotions.free_months and treat NULL as lifetime, with a one-month floor so
-- an R1 payer is never born expired). This script repairs members created
-- BEFORE that fix.
--
-- Idempotent: only extends affected lifetime-promo subscriptions; safe to re-run.
-- Never deletes data.
-- =============================================================================

-- 1) Extend the affected subscriptions to lifetime and reactivate them.
WITH affected AS (
    SELECT s.id AS sub_id
    FROM public.subscriptions s
    JOIN public.promotions p ON p.id = s.promotion_id
    WHERE s.plan_type = 'promotion_intro'
      AND s.user_id IS NOT NULL
      AND p.free_months IS NULL                                   -- lifetime promo
      AND s.current_period_end < now() + INTERVAL '50 years'      -- not already lifetime
)
UPDATE public.subscriptions s
SET current_period_end = now() + INTERVAL '100 years',
    free_period_end    = now() + INTERVAL '100 years',
    status             = 'active',
    updated_at         = now()
FROM affected a
WHERE s.id = a.sub_id;

-- 2) Refresh the members' active QR codes to match the lifetime period.
UPDATE public.user_qr_codes q
SET expires_at = now() + INTERVAL '100 years',
    is_active  = true,
    updated_at = now()
FROM public.subscriptions s
JOIN public.promotions p ON p.id = s.promotion_id
WHERE q.user_id = s.user_id
  AND s.plan_type = 'promotion_intro'
  AND p.free_months IS NULL
  AND q.expires_at < now() + INTERVAL '50 years';

-- 3) Reflect active membership on the profile.
UPDATE public.profiles pr
SET subscription = 'active',
    updated_at   = now()
FROM public.subscriptions s
JOIN public.promotions p ON p.id = s.promotion_id
WHERE pr.id = s.user_id
  AND s.plan_type = 'promotion_intro'
  AND p.free_months IS NULL
  AND pr.subscription IS DISTINCT FROM 'active';
