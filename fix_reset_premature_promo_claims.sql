-- ============================================================
-- Fix: reset prematurely "claimed" promo participant emails
--
-- Root cause: PromotionDetailPage._signUp() previously marked
-- promotion_participant_emails.is_claimed = true as soon as a member
-- tapped "Sign Up" on a promo banner, BEFORE any payment.
--
-- The R1 intro price is gated by is_claimed = false (see
-- check_promo_eligibility_for_email). So a premature claim removed the
-- R1 offer and the member was charged the standard R99 instead.
--
-- This script restores R1 eligibility for members who were claimed but
-- never actually completed the intro payment. Members who DID pay have a
-- subscription row referencing their participant id and are left untouched.
-- ============================================================

-- 1) Diagnostic: participants that look prematurely claimed
--    (claimed, but no intro subscription references them)
SELECT
  ppe.id            AS participant_id,
  ppe.promotion_id,
  ppe.email,
  ppe.is_claimed,
  ppe.claimed_by,
  ppe.claimed_at
FROM public.promotion_participant_emails ppe
WHERE ppe.is_claimed = true
  AND NOT EXISTS (
    SELECT 1
    FROM public.subscriptions s
    WHERE s.promo_participant_id = ppe.id
  )
ORDER BY ppe.claimed_at DESC NULLS LAST;

-- 2) Fix: reset those rows so the R1 offer becomes available again.
UPDATE public.promotion_participant_emails ppe
SET is_claimed = false,
    claimed_by = NULL,
    claimed_at = NULL
WHERE ppe.is_claimed = true
  AND NOT EXISTS (
    SELECT 1
    FROM public.subscriptions s
    WHERE s.promo_participant_id = ppe.id
  );
