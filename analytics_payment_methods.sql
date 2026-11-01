-- Analytics queries for in-app vs in-store payment tracking
-- Run these queries to get insights on payment method usage

-- =============================================================================
-- 1. OVERALL PAYMENT METHOD BREAKDOWN
-- =============================================================================
-- Total payments by method with amounts
SELECT 
    payment_method,
    COUNT(*) as total_transactions,
    SUM(amount) as total_revenue,
    AVG(amount) as average_transaction,
    MIN(amount) as min_amount,
    MAX(amount) as max_amount
FROM deal_receipts
GROUP BY payment_method
ORDER BY total_revenue DESC;

-- =============================================================================
-- 2. PAYMENT METHOD TRENDS OVER TIME (MONTHLY)
-- =============================================================================
-- Monthly breakdown of payment methods
SELECT 
    DATE_TRUNC('month', created_at) as month,
    payment_method,
    COUNT(*) as transactions,
    SUM(amount) as revenue
FROM deal_receipts
GROUP BY DATE_TRUNC('month', created_at), payment_method
ORDER BY month DESC, payment_method;

-- =============================================================================
-- 3. PAYMENT METHOD TRENDS OVER TIME (DAILY - LAST 30 DAYS)
-- =============================================================================
SELECT 
    DATE(created_at) as date,
    payment_method,
    COUNT(*) as transactions,
    SUM(amount) as revenue
FROM deal_receipts
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at), payment_method
ORDER BY date DESC, payment_method;

-- =============================================================================
-- 4. TOP BUSINESSES BY PAYMENT METHOD
-- =============================================================================
-- Which businesses prefer which payment methods
SELECT 
    business_name,
    payment_method,
    COUNT(*) as transactions,
    SUM(amount) as total_revenue
FROM deal_receipts
GROUP BY business_name, payment_method
ORDER BY total_revenue DESC
LIMIT 20;

-- =============================================================================
-- 5. MEMBER PAYMENT PREFERENCES
-- =============================================================================
-- How many members use each payment method
SELECT 
    payment_method,
    COUNT(DISTINCT member_id) as unique_members,
    COUNT(*) as total_transactions,
    SUM(amount) as total_spent
FROM deal_receipts
GROUP BY payment_method
ORDER BY unique_members DESC;

-- =============================================================================
-- 6. PAYMENT METHOD CONVERSION RATES
-- =============================================================================
-- Success rate: authorizations approved vs actually completed by payment method
SELECT 
    da.payment_method,
    COUNT(DISTINCT da.id) as total_authorizations,
    COUNT(DISTINCT CASE WHEN da.status = 'approved' THEN da.id END) as approved,
    COUNT(DISTINCT CASE WHEN da.status = 'completed' THEN da.id END) as completed,
    COUNT(DISTINCT dr.id) as receipts_issued,
    ROUND(
        100.0 * COUNT(DISTINCT CASE WHEN da.status = 'completed' THEN da.id END) / 
        NULLIF(COUNT(DISTINCT CASE WHEN da.status = 'approved' THEN da.id END), 0), 
        2
    ) as completion_rate_percent
FROM deal_authorizations da
LEFT JOIN deal_receipts dr ON da.id = dr.deal_authorization_id
WHERE da.payment_method IS NOT NULL
GROUP BY da.payment_method
ORDER BY completion_rate_percent DESC;

-- =============================================================================
-- 7. RECENT TRANSACTIONS BY PAYMENT METHOD (LAST 50)
-- =============================================================================
SELECT 
    receipt_number,
    payment_method,
    business_name,
    member_name,
    amount,
    created_at
FROM deal_receipts
ORDER BY created_at DESC
LIMIT 50;

-- =============================================================================
-- 8. PAYMENT METHOD DISTRIBUTION BY BUSINESS CATEGORY
-- =============================================================================
-- Requires businesses.category to be populated
SELECT 
    b.category,
    dr.payment_method,
    COUNT(*) as transactions,
    SUM(dr.amount) as revenue
FROM deal_receipts dr
JOIN businesses b ON dr.business_id = b.id
WHERE b.category IS NOT NULL
GROUP BY b.category, dr.payment_method
ORDER BY b.category, revenue DESC;

-- =============================================================================
-- 9. AVERAGE TIME TO COMPLETE BY PAYMENT METHOD
-- =============================================================================
-- How long does each payment method take from authorization to completion
SELECT 
    da.payment_method,
    COUNT(*) as completed_transactions,
    AVG(EXTRACT(EPOCH FROM (da.completed_at - da.created_at))/60) as avg_minutes_to_complete,
    MIN(EXTRACT(EPOCH FROM (da.completed_at - da.created_at))/60) as min_minutes,
    MAX(EXTRACT(EPOCH FROM (da.completed_at - da.created_at))/60) as max_minutes
FROM deal_authorizations da
WHERE da.completed_at IS NOT NULL 
  AND da.payment_method IS NOT NULL
GROUP BY da.payment_method
ORDER BY avg_minutes_to_complete;

-- =============================================================================
-- 10. PAYMENT METHOD SUMMARY (CURRENT PERIOD)
-- =============================================================================
-- Quick snapshot for dashboard
SELECT 
    'Total Revenue' as metric,
    payment_method,
    SUM(amount) as value
FROM deal_receipts
WHERE created_at >= DATE_TRUNC('month', NOW())
GROUP BY payment_method

UNION ALL

SELECT 
    'Total Transactions' as metric,
    payment_method,
    COUNT(*)::numeric as value
FROM deal_receipts
WHERE created_at >= DATE_TRUNC('month', NOW())
GROUP BY payment_method

UNION ALL

SELECT 
    'Unique Members' as metric,
    payment_method,
    COUNT(DISTINCT member_id)::numeric as value
FROM deal_receipts
WHERE created_at >= DATE_TRUNC('month', NOW())
GROUP BY payment_method

ORDER BY metric, payment_method;

-- =============================================================================
-- 11. PAYMENT METHOD PERCENTAGE BREAKDOWN
-- =============================================================================
-- What percentage of revenue comes from each method
WITH totals AS (
    SELECT 
        SUM(amount) as total_revenue,
        COUNT(*) as total_transactions
    FROM deal_receipts
)
SELECT 
    dr.payment_method,
    COUNT(*) as transactions,
    SUM(dr.amount) as revenue,
    ROUND(100.0 * COUNT(*) / t.total_transactions, 2) as transaction_percentage,
    ROUND(100.0 * SUM(dr.amount) / t.total_revenue, 2) as revenue_percentage
FROM deal_receipts dr
CROSS JOIN totals t
GROUP BY dr.payment_method, t.total_transactions, t.total_revenue
ORDER BY revenue DESC;

-- =============================================================================
-- 12. COMPARE CURRENT MONTH VS PREVIOUS MONTH
-- =============================================================================
SELECT 
    payment_method,
    SUM(CASE WHEN created_at >= DATE_TRUNC('month', NOW()) 
        THEN amount ELSE 0 END) as current_month_revenue,
    SUM(CASE WHEN created_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
        AND created_at < DATE_TRUNC('month', NOW())
        THEN amount ELSE 0 END) as previous_month_revenue,
    COUNT(CASE WHEN created_at >= DATE_TRUNC('month', NOW()) 
        THEN 1 END) as current_month_transactions,
    COUNT(CASE WHEN created_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
        AND created_at < DATE_TRUNC('month', NOW())
        THEN 1 END) as previous_month_transactions
FROM deal_receipts
WHERE created_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
GROUP BY payment_method
ORDER BY current_month_revenue DESC;

-- =============================================================================
-- 13. CREATE A VIEW FOR EASY DASHBOARD ACCESS
-- =============================================================================
-- Create a materialized view that can be refreshed periodically
CREATE OR REPLACE VIEW payment_method_analytics AS
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

-- Query the view
-- SELECT * FROM payment_method_analytics WHERE transaction_date >= NOW() - INTERVAL '30 days';

-- =============================================================================
-- 14. TRUSTED PARTNER PREFERENCE ANALYSIS
-- =============================================================================
-- Which trusted partners get more in-store vs in-app payments
SELECT 
    dr.business_name,
    dr.trusted_partner_id,
    COUNT(*) FILTER (WHERE dr.payment_method = 'in_app') as in_app_count,
    COUNT(*) FILTER (WHERE dr.payment_method = 'pos') as pos_count,
    SUM(dr.amount) FILTER (WHERE dr.payment_method = 'in_app') as in_app_revenue,
    SUM(dr.amount) FILTER (WHERE dr.payment_method = 'pos') as pos_revenue,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE dr.payment_method = 'pos') / 
        NULLIF(COUNT(*), 0), 
        2
    ) as pos_percentage
FROM deal_receipts dr
GROUP BY dr.business_name, dr.trusted_partner_id
HAVING COUNT(*) >= 5  -- Only show businesses with at least 5 transactions
ORDER BY pos_percentage DESC;

-- =============================================================================
-- INSTRUCTIONS FOR USE
-- =============================================================================
-- 1. Run individual queries as needed for specific insights
-- 2. Query #1 gives you the quickest overall summary
-- 3. Query #11 shows percentage breakdown (good for reports)
-- 4. Query #13 creates a view for dashboard integration
-- 5. All queries work with the existing deal_receipts table structure
-- 6. payment_method values are: 'in_app' or 'pos'
