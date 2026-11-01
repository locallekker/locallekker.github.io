-- =====================================================
-- AUTO-RENEWAL MONITORING & MAINTENANCE QUERIES
-- Use these queries to monitor subscription health
-- =====================================================

-- =============================================================================
-- SUBSCRIPTION HEALTH OVERVIEW
-- =============================================================================

-- Current subscription status breakdown
SELECT 
    status,
    COUNT(*) as member_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM subscriptions
GROUP BY status
ORDER BY member_count DESC;

-- Expected output:
-- status         | member_count | percentage
-- ---------------|--------------|------------
-- active         | 850          | 85.00
-- payment_failed | 30           | 3.00
-- expired        | 100          | 10.00
-- cancelled      | 20           | 2.00


-- =============================================================================
-- RECENT AUTO-RENEWALS (Last 7 Days)
-- =============================================================================

SELECT 
    p.email,
    p.name,
    s.current_period_end,
    s.status,
    s.updated_at as renewed_at,
    CASE 
        WHEN s.updated_at > NOW() - INTERVAL '1 day' THEN '24h'
        WHEN s.updated_at > NOW() - INTERVAL '3 days' THEN '3d'
        WHEN s.updated_at > NOW() - INTERVAL '7 days' THEN '7d'
    END as renewal_age
FROM subscriptions s
JOIN profiles p ON s.user_id = p.id
WHERE s.updated_at > NOW() - INTERVAL '7 days'
  AND s.status = 'active'
  AND s.paystack_subscription_code IS NOT NULL
ORDER BY s.updated_at DESC
LIMIT 50;


-- =============================================================================
-- PAYMENT FAILURES - ACTIVE ISSUES
-- =============================================================================

-- Members with payment failures who need attention
SELECT 
    p.email,
    p.name,
    s.paystack_subscription_code,
    s.updated_at as failed_at,
    n.is_read as notification_read,
    n.created_at as notification_sent_at,
    EXTRACT(DAY FROM NOW() - s.updated_at) as days_since_failure
FROM subscriptions s
JOIN profiles p ON s.user_id = p.id
LEFT JOIN notifications n ON n.user_id = p.id 
    AND n.type = 'payment_failure' 
    AND n.created_at >= s.updated_at
WHERE s.status = 'payment_failed'
ORDER BY s.updated_at DESC;

-- Expected actions:
-- - Days 0-3: User should update payment method
-- - Days 4-7: Send follow-up reminder
-- - Days 8+: Consider manual outreach


-- =============================================================================
-- NOTIFICATION DELIVERY SUCCESS
-- =============================================================================

-- Check if payment failure notifications are being created and read
SELECT 
    n.type,
    COUNT(*) as total_notifications,
    COUNT(*) FILTER (WHERE n.is_read = true) as read_count,
    COUNT(*) FILTER (WHERE n.is_read = false) as unread_count,
    ROUND(
        COUNT(*) FILTER (WHERE n.is_read = true) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) as read_percentage
FROM notifications n
WHERE n.created_at > NOW() - INTERVAL '30 days'
  AND n.type IN ('payment_failure', 'subscription_renewal')
GROUP BY n.type;

-- Target read rate: >70% for payment failures


-- =============================================================================
-- WEBHOOK PROCESSING CHECK
-- =============================================================================

-- Identify subscriptions that should have renewed but haven't
-- (Potential webhook delivery issues)
SELECT 
    p.email,
    s.current_period_end,
    s.status,
    s.paystack_subscription_code,
    s.updated_at,
    EXTRACT(DAY FROM NOW() - s.current_period_end) as days_overdue
FROM subscriptions s
JOIN profiles p ON s.user_id = p.id
WHERE s.current_period_end < NOW() - INTERVAL '3 days'
  AND s.status = 'active'
  AND s.paystack_subscription_code IS NOT NULL
ORDER BY s.current_period_end ASC;

-- If this returns results, check webhook logs


-- =============================================================================
-- QR CODE ACTIVATION STATUS
-- =============================================================================

-- Verify QR codes match subscription status
SELECT 
    s.status as subscription_status,
    q.is_active as qr_active,
    COUNT(*) as member_count,
    CASE 
        WHEN s.status = 'active' AND q.is_active = true THEN '✅ Correct'
        WHEN s.status IN ('payment_failed', 'expired', 'cancelled') AND q.is_active = false THEN '✅ Correct'
        ELSE '❌ Mismatch'
    END as status_match
FROM subscriptions s
JOIN user_qr_codes q ON q.user_id = s.user_id
WHERE q.created_at = (
    SELECT MAX(created_at) 
    FROM user_qr_codes 
    WHERE user_id = s.user_id
)
GROUP BY s.status, q.is_active
ORDER BY s.status, q.is_active;


-- =============================================================================
-- REVENUE TRACKING
-- =============================================================================

-- Monthly revenue from auto-renewals
SELECT 
    DATE_TRUNC('month', pm.completed_at) as renewal_month,
    COUNT(*) as renewal_count,
    SUM(pm.amount) as gross_revenue,
    SUM(pm.amount * 0.015 + 2) as paystack_fees,
    SUM(pm.amount - (pm.amount * 0.015 + 2)) as net_revenue
FROM payments pm
JOIN subscriptions s ON pm.user_id = s.user_id
WHERE pm.status = 'completed'
  AND pm.completed_at > NOW() - INTERVAL '6 months'
  AND s.paystack_subscription_code IS NOT NULL
GROUP BY DATE_TRUNC('month', pm.completed_at)
ORDER BY renewal_month DESC;


-- =============================================================================
-- CHURN ANALYSIS
-- =============================================================================

-- Members who cancelled after payment failure
SELECT 
    p.email,
    s.status,
    s.updated_at as status_changed_at,
    pm.completed_at as last_payment_at,
    EXTRACT(DAY FROM s.updated_at - pm.completed_at) as days_as_member
FROM subscriptions s
JOIN profiles p ON s.user_id = p.id
LEFT JOIN LATERAL (
    SELECT completed_at
    FROM payments
    WHERE user_id = s.user_id
      AND status = 'completed'
    ORDER BY completed_at DESC
    LIMIT 1
) pm ON true
WHERE s.status = 'cancelled'
  AND s.updated_at > NOW() - INTERVAL '30 days'
ORDER BY s.updated_at DESC;


-- =============================================================================
-- UPCOMING RENEWALS (Next 7 Days)
-- =============================================================================

-- Predict upcoming renewal volume
SELECT 
    DATE(s.current_period_end) as renewal_date,
    COUNT(*) as renewals_due,
    SUM(99.00) as expected_revenue
FROM subscriptions s
WHERE s.status = 'active'
  AND s.paystack_subscription_code IS NOT NULL
  AND s.current_period_end BETWEEN NOW() AND NOW() + INTERVAL '7 days'
GROUP BY DATE(s.current_period_end)
ORDER BY renewal_date ASC;


-- =============================================================================
-- MANUAL INTERVENTION QUERIES (TEMPLATES - DO NOT RUN AS-IS)
-- =============================================================================

-- IMPORTANT: These are templates. Replace 'REPLACE_WITH_USER_ID' with actual UUID
-- before running. Uncomment the queries you need.

/*
-- Fix: Manually reactivate subscription after payment success
-- (Use only if webhook failed to process)
UPDATE subscriptions
SET status = 'active',
    current_period_end = current_period_end + INTERVAL '30 days',
    updated_at = NOW()
WHERE user_id = 'REPLACE_WITH_USER_ID'
  AND status = 'payment_failed';

-- Then reactivate QR code
UPDATE user_qr_codes
SET is_active = true,
    updated_at = NOW()
WHERE user_id = 'REPLACE_WITH_USER_ID'
  AND created_at = (
    SELECT MAX(created_at)
    FROM user_qr_codes
    WHERE user_id = 'REPLACE_WITH_USER_ID'
  );

-- And update profile
UPDATE profiles
SET subscription = 'active',
    updated_at = NOW()
WHERE id = 'REPLACE_WITH_USER_ID';
*/


-- =============================================================================
-- DAILY HEALTH CHECK (Run Every Morning)
-- =============================================================================

-- Comprehensive daily report
WITH daily_stats AS (
    SELECT 
        (SELECT COUNT(*) FROM subscriptions WHERE status = 'active') as active_subs,
        (SELECT COUNT(*) FROM subscriptions WHERE status = 'payment_failed') as failed_payments,
        (SELECT COUNT(*) FROM subscriptions WHERE status = 'expired') as expired_subs,
        (SELECT COUNT(*) FROM subscriptions 
         WHERE updated_at > NOW() - INTERVAL '24 hours' 
         AND status = 'active') as renewals_24h,
        (SELECT COUNT(*) FROM notifications 
         WHERE created_at > NOW() - INTERVAL '24 hours' 
         AND type = 'payment_failure') as failures_24h,
        (SELECT COUNT(*) FROM subscriptions 
         WHERE current_period_end < NOW() 
         AND status = 'active' 
         AND paystack_subscription_code IS NOT NULL) as webhook_issues
)
SELECT 
    '📊 Daily Subscription Health Report' as report_title,
    TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI') as generated_at,
    active_subs as "✅ Active Subscriptions",
    renewals_24h as "🔄 Renewals (24h)",
    failed_payments as "❌ Payment Failures",
    failures_24h as "🚨 New Failures (24h)",
    expired_subs as "⏰ Expired",
    webhook_issues as "⚠️  Webhook Issues"
FROM daily_stats;


-- =============================================================================
-- EMERGENCY CLEANUP
-- =============================================================================

-- Find and fix stuck payment_failed statuses (older than 30 days)
-- These likely need manual intervention
SELECT 
    p.email,
    s.status,
    s.updated_at,
    EXTRACT(DAY FROM NOW() - s.updated_at) as days_stuck,
    s.paystack_subscription_code
FROM subscriptions s
JOIN profiles p ON s.user_id = p.id
WHERE s.status = 'payment_failed'
  AND s.updated_at < NOW() - INTERVAL '30 days'
ORDER BY s.updated_at ASC;

-- Decision tree:
-- - If Paystack shows subscription cancelled → Update status to 'cancelled'
-- - If Paystack shows subscription active → Manually sync (see above)
-- - If no Paystack subscription → Create new subscription flow


-- =============================================================================
-- NOTIFICATION CLEANUP (Optional)
-- =============================================================================

-- Delete old read notifications (older than 90 days)
DELETE FROM notifications
WHERE is_read = true
  AND created_at < NOW() - INTERVAL '90 days'
  AND type NOT IN ('payment_failure'); -- Keep payment failures for records

-- Archive important notifications instead
CREATE TABLE IF NOT EXISTS notifications_archive (
    LIKE notifications INCLUDING ALL
);

INSERT INTO notifications_archive
SELECT * FROM notifications
WHERE is_read = true
  AND created_at < NOW() - INTERVAL '90 days'
  AND type = 'payment_failure';
