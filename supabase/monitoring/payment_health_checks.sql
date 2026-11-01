-- =============================================================================
-- Local Lekker - Payment health checks (READ-ONLY)
-- =============================================================================
-- Run manually in the Supabase SQL editor (or psql) to spot payment issues
-- early. Every statement here is a SELECT: nothing is modified.
--
-- This file is intentionally NOT under supabase/migrations so it is never
-- applied automatically. Checks 1-6 should normally return zero rows.
-- =============================================================================


-- 1. Completed in-app deals (last 30 days) with no virtual receipt.
--    Member paid, but the receipt insert failed or never ran.
SELECT da.id AS deal_id, da.member_id, da.amount, da.completed_at
FROM public.deal_authorizations da
WHERE da.status = 'completed'
  AND da.payment_method = 'in_app'
  AND da.completed_at > NOW() - INTERVAL '30 days'
  AND NOT EXISTS (
    SELECT 1 FROM public.virtual_receipts vr
    WHERE vr.deal_authorization_id = da.id
  )
ORDER BY da.completed_at DESC;


-- 2. Deals with more than one virtual receipt (possible double processing).
SELECT vr.deal_authorization_id, COUNT(*) AS receipt_count,
       ARRAY_AGG(vr.receipt_number ORDER BY vr.created_at) AS receipt_numbers
FROM public.virtual_receipts vr
GROUP BY vr.deal_authorization_id
HAVING COUNT(*) > 1
ORDER BY receipt_count DESC;


-- 3. Approved deals stuck for more than 1 hour without completing.
--    Usually an abandoned checkout, or a payment the app/webhook did not
--    record. Cross-check the reference in the Paystack dashboard.
SELECT da.id AS deal_id, da.member_id, da.amount, da.approved_at
FROM public.deal_authorizations da
WHERE da.status = 'approved'
  AND da.approved_at < NOW() - INTERVAL '1 hour'
  AND da.approved_at > NOW() - INTERVAL '14 days'
ORDER BY da.approved_at DESC;


-- 4. Subscriptions still marked active although their period has ended.
SELECT s.id, s.user_id, s.plan_type, s.auto_renew,
       s.current_period_end, s.next_payment_date
FROM public.subscriptions s
WHERE s.status = 'active'
  AND s.current_period_end < NOW() - INTERVAL '1 day'
ORDER BY s.current_period_end;


-- 5. Users with more than one active subscription row.
SELECT s.user_id, COUNT(*) AS active_rows
FROM public.subscriptions s
WHERE s.status = 'active'
GROUP BY s.user_id
HAVING COUNT(*) > 1;


-- 6. Active, in-period subscriptions with no usable QR code (member paid
--    but can't redeem deals).
SELECT s.user_id, s.current_period_end
FROM public.subscriptions s
WHERE s.status = 'active'
  AND s.current_period_end > NOW()
  AND NOT EXISTS (
    SELECT 1 FROM public.user_qr_codes q
    WHERE q.user_id = s.user_id
      AND q.is_active = TRUE
      AND (q.expires_at IS NULL OR q.expires_at > NOW())
  );


-- 7. Schema objects the app/Edge Functions rely on that come from root SQL
--    scripts rather than canonical migrations. Any row with present = false
--    means that script has not been applied to this database.
SELECT 'column' AS kind, 'subscriptions.renewal_charge_cents' AS object,
       EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'subscriptions'
                 AND column_name = 'renewal_charge_cents') AS present
UNION ALL
SELECT 'column', 'subscriptions.paystack_subscription_code',
       EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'subscriptions'
                 AND column_name = 'paystack_subscription_code')
UNION ALL
SELECT 'table', 'deal_receipts',
       to_regclass('public.deal_receipts') IS NOT NULL
UNION ALL
SELECT 'view', 'subscriptions_due_for_renewal',
       to_regclass('public.subscriptions_due_for_renewal') IS NOT NULL
UNION ALL
SELECT 'view', 'pending_payment_reconciliation_candidates',
       to_regclass('public.pending_payment_reconciliation_candidates') IS NOT NULL
UNION ALL
SELECT 'table', 'payment_reconciliation_log',
       to_regclass('public.payment_reconciliation_log') IS NOT NULL
UNION ALL
SELECT 'function', 'get_next_receipt_number(uuid)',
       to_regprocedure('public.get_next_receipt_number(uuid)') IS NOT NULL
UNION ALL
SELECT 'function', 'get_subscription_status',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.proname = 'get_subscription_status');
