-- =============================================================================
-- FIX: Remove SECURITY DEFINER from payment_method_analytics view
-- Issue: Security Advisor flagged SECURITY DEFINER as a security risk
-- Solution: Recreate view as SECURITY INVOKER (default, safer)
-- =============================================================================

-- Drop and recreate the view without SECURITY DEFINER
DROP VIEW IF EXISTS payment_method_analytics;

CREATE OR REPLACE VIEW payment_method_analytics 
WITH (security_invoker = true)
AS
SELECT 
    payment_method,
    DATE_TRUNC('day', created_at)::date as transaction_date,
    COUNT(*) as daily_transactions,
    SUM(amount) as daily_revenue,
    COUNT(DISTINCT member_id) as unique_members,
    COUNT(DISTINCT business_id) as unique_businesses,
    AVG(amount) as avg_transaction_amount
FROM deal_receipts
GROUP BY payment_method, DATE_TRUNC('day', created_at)
ORDER BY transaction_date DESC, payment_method;

-- Grant appropriate permissions
-- Admins can view analytics
GRANT SELECT ON payment_method_analytics TO authenticated;

-- Add RLS policy if needed (views inherit RLS from underlying tables)
-- The deal_receipts table should already have RLS policies
