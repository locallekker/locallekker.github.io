-- Create comprehensive admin analytics RPC function
-- This provides all data needed for a rich admin dashboard

-- Drop existing function
DROP FUNCTION IF EXISTS public.get_admin_analytics();

-- Create new comprehensive analytics function
CREATE OR REPLACE FUNCTION public.get_admin_analytics()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSON;
  v_total_members INT;
  v_total_trusted_partners INT;
  v_total_businesses INT;
  v_total_deals INT;
  v_active_deals INT;
  v_total_revenue NUMERIC;
  v_in_app_revenue NUMERIC;
  v_pos_revenue NUMERIC;
  v_monthly_revenue NUMERIC;
  v_monthly_revenue_month TEXT;
  v_daily_revenue NUMERIC;
  v_avg_deal_value NUMERIC;
  v_completion_rate NUMERIC;
  v_top_businesses JSON;
  v_payment_method_breakdown JSON;
  v_recent_transactions JSON;
  v_monthly_trends JSON;
  v_member_growth JSON;
  v_deal_status_breakdown JSON;
BEGIN
  -- Total Members
  SELECT COUNT(*) INTO v_total_members
  FROM profiles
  WHERE role = 'member';

  -- Total Trusted Partners
  SELECT COUNT(*) INTO v_total_trusted_partners
  FROM profiles
  WHERE role = 'trusted_partner';

  -- Total Businesses
  SELECT COUNT(*) INTO v_total_businesses
  FROM businesses;

  -- Total Deals (all time)
  SELECT COUNT(*) INTO v_total_deals
  FROM deal_authorizations;

  -- Active Deals (pending or approved)
  SELECT COUNT(*) INTO v_active_deals
  FROM deal_authorizations
  WHERE status IN ('pending', 'approved');

  -- Total Revenue (all time - completed deals only)
  SELECT COALESCE(SUM(amount), 0) INTO v_total_revenue
  FROM deal_authorizations
  WHERE status = 'completed';

  -- In-App Revenue
  SELECT COALESCE(SUM(amount), 0) INTO v_in_app_revenue
  FROM deal_authorizations
  WHERE payment_method = 'in_app'
    AND status = 'completed';

  -- POS Revenue
  SELECT COALESCE(SUM(amount), 0) INTO v_pos_revenue
  FROM deal_authorizations
  WHERE payment_method = 'pos'
    AND status = 'completed';

  -- Monthly Revenue (most recent month with transactions, or current month if it has transactions)
  SELECT 
    COALESCE(SUM(amount), 0),
    TO_CHAR(DATE_TRUNC('month', MAX(created_at)), 'Month YYYY')
  INTO v_monthly_revenue, v_monthly_revenue_month
  FROM deal_authorizations
  WHERE DATE_TRUNC('month', created_at) = (
    SELECT DATE_TRUNC('month', MAX(created_at))
    FROM deal_authorizations
    WHERE status = 'completed'
  )
  AND status = 'completed';

  -- Daily Revenue (today)
  SELECT COALESCE(SUM(amount), 0) INTO v_daily_revenue
  FROM deal_authorizations
  WHERE DATE(created_at) = CURRENT_DATE
    AND status = 'completed';

  -- Average Deal Value
  SELECT COALESCE(AVG(amount), 0) INTO v_avg_deal_value
  FROM deal_authorizations
  WHERE status = 'completed';

  -- Completion Rate (approved -> completed)
  SELECT COALESCE(
    ROUND(
      100.0 * COUNT(*) FILTER (WHERE status = 'completed') / 
      NULLIF(COUNT(*) FILTER (WHERE status IN ('approved', 'completed')), 0),
      2
    ),
    0
  ) INTO v_completion_rate
  FROM deal_authorizations;

  -- Top 10 Businesses by Revenue
  SELECT JSON_AGG(
    JSON_BUILD_OBJECT(
      'business_id', business_id,
      'business_name', business_name,
      'revenue', revenue,
      'transactions', transactions
    )
  ) INTO v_top_businesses
  FROM (
    SELECT 
      da.business_id,
      b.name as business_name,
      SUM(da.amount) as revenue,
      COUNT(*) as transactions
    FROM deal_authorizations da
    LEFT JOIN businesses b ON da.business_id = b.id
    WHERE da.status = 'completed'
      AND da.amount IS NOT NULL
    GROUP BY da.business_id, b.name
    HAVING COUNT(*) > 0
    ORDER BY revenue DESC
    LIMIT 10
  ) top_biz;

  -- Payment Method Breakdown
  SELECT JSON_AGG(
    JSON_BUILD_OBJECT(
      'payment_method', payment_method,
      'transactions', transactions,
      'revenue', revenue,
      'percentage', percentage
    )
  ) INTO v_payment_method_breakdown
  FROM (
    WITH totals AS (
      SELECT 
        SUM(amount) as total_revenue,
        COUNT(*) as total_transactions
      FROM deal_authorizations
      WHERE status = 'completed'
    )
    SELECT 
      COALESCE(da.payment_method, 'unknown') as payment_method,
      COUNT(*) as transactions,
      SUM(da.amount) as revenue,
      ROUND(100.0 * SUM(da.amount) / NULLIF(t.total_revenue, 0), 2) as percentage
    FROM deal_authorizations da
    CROSS JOIN totals t
    WHERE da.status = 'completed'
    GROUP BY da.payment_method, t.total_revenue
    ORDER BY revenue DESC
  ) payment_breakdown;

  -- Recent 10 Transactions
  SELECT JSON_AGG(
    JSON_BUILD_OBJECT(
      'id', id,
      'business_name', business_name,
      'member_name', member_name,
      'amount', amount,
      'payment_method', payment_method,
      'created_at', created_at,
      'status', status
    )
  ) INTO v_recent_transactions
  FROM (
    SELECT 
      da.id,
      b.name as business_name,
      CONCAT(p.name, ' ', p.surname) as member_name,
      da.amount,
      da.payment_method,
      da.created_at,
      da.status
    FROM deal_authorizations da
    LEFT JOIN businesses b ON da.business_id = b.id
    LEFT JOIN profiles p ON da.member_id = p.id
    WHERE da.status = 'completed'
    ORDER BY da.created_at DESC
    LIMIT 10
  ) recent;

  -- Monthly Trends (last 6 months)
  SELECT JSON_AGG(
    JSON_BUILD_OBJECT(
      'month', month,
      'revenue', revenue,
      'transactions', transactions
    ) ORDER BY month DESC
  ) INTO v_monthly_trends
  FROM (
    SELECT 
      TO_CHAR(DATE_TRUNC('month', created_at), 'YYYY-MM') as month,
      SUM(amount) as revenue,
      COUNT(*) as transactions
    FROM deal_authorizations
    WHERE created_at >= NOW() - INTERVAL '6 months'
      AND status = 'completed'
    GROUP BY DATE_TRUNC('month', created_at)
    ORDER BY DATE_TRUNC('month', created_at) DESC
    LIMIT 6
  ) trends;

  -- Member Growth (last 30 days)
  SELECT JSON_AGG(
    JSON_BUILD_OBJECT(
      'date', signup_date,
      'new_members', new_members
    ) ORDER BY signup_date DESC
  ) INTO v_member_growth
  FROM (
    SELECT 
      DATE(created_at) as signup_date,
      COUNT(*) as new_members
    FROM profiles
    WHERE role = 'member' 
      AND created_at >= NOW() - INTERVAL '30 days'
    GROUP BY DATE(created_at)
    ORDER BY DATE(created_at) DESC
  ) growth;

  -- Deal Status Breakdown
  SELECT JSON_AGG(
    JSON_BUILD_OBJECT(
      'status', status,
      'count', count
    )
  ) INTO v_deal_status_breakdown
  FROM (
    SELECT 
      status,
      COUNT(*) as count
    FROM deal_authorizations
    GROUP BY status
  ) status_breakdown;

  -- Build final result
  SELECT JSON_BUILD_OBJECT(
    'overview', JSON_BUILD_OBJECT(
      'total_members', v_total_members,
      'total_trusted_partners', v_total_trusted_partners,
      'total_businesses', v_total_businesses,
      'total_deals', v_total_deals,
      'monthly_revenue_month', TRIM(v_monthly_revenue_month),
      'active_deals', v_active_deals,
      'total_revenue', v_total_revenue,
      'monthly_revenue', v_monthly_revenue,
      'daily_revenue', v_daily_revenue,
      'avg_deal_value', v_avg_deal_value,
      'completion_rate', v_completion_rate
    ),
    'payment_methods', JSON_BUILD_OBJECT(
      'in_app_revenue', v_in_app_revenue,
      'pos_revenue', v_pos_revenue,
      'breakdown', v_payment_method_breakdown
    ),
    'top_businesses', v_top_businesses,
    'recent_transactions', v_recent_transactions,
    'monthly_trends', v_monthly_trends,
    'member_growth', v_member_growth,
    'deal_status_breakdown', v_deal_status_breakdown
  ) INTO result;

  RETURN result;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.get_admin_analytics() TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.get_admin_analytics() IS 
'Returns comprehensive analytics for admin dashboard including revenue, payment methods, deals, and trends';
