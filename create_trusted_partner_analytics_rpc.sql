-- Create comprehensive trusted partner analytics RPC function
-- This provides all data needed for a rich trusted partner dashboard

-- Drop existing function if it exists
DROP FUNCTION IF EXISTS public.get_trusted_partner_analytics(UUID);

-- Create new comprehensive analytics function for trusted partners
CREATE OR REPLACE FUNCTION public.get_trusted_partner_analytics(p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSON;
  v_business_id UUID;
  v_total_deals_created INT;
  v_active_deals INT;
  v_total_turnover NUMERIC;
  v_in_app_income NUMERIC;
  v_pos_income NUMERIC;
  v_monthly_turnover NUMERIC;
  v_weekly_turnover NUMERIC;
  v_daily_turnover NUMERIC;
  v_avg_deal_value NUMERIC;
  v_completion_rate NUMERIC;
  v_pending_requests INT;
  v_approved_requests INT;
  v_completed_deals INT;
  v_rejected_requests INT;
  v_top_deals JSON;
  v_recent_transactions JSON;
  v_monthly_trends JSON;
  v_payment_method_breakdown JSON;
  v_deal_status_breakdown JSON;
  v_member_count INT;
  v_repeat_customer_count INT;
BEGIN
  -- Get the business_id for this trusted partner
  SELECT id INTO v_business_id
  FROM businesses
  WHERE owner_member_id = p_user_id
  LIMIT 1;

  -- If no business found, return empty result
  IF v_business_id IS NULL THEN
    RETURN json_build_object(
      'error', 'No business found for this user',
      'overview', json_build_object(
        'total_deals_created', 0,
        'active_deals', 0,
        'total_turnover', 0,
        'in_app_income', 0,
        'pos_income', 0,
        'monthly_turnover', 0,
        'weekly_turnover', 0,
        'daily_turnover', 0,
        'avg_deal_value', 0,
        'completion_rate', 0
      )
    );
  END IF;

  -- Total Deals Created (all discounts created by this TP)
  SELECT COUNT(*) INTO v_total_deals_created
  FROM trusted_partner_discounts
  WHERE trusted_partner_id = p_user_id;

  -- Active Deals (is_active = true)
  SELECT COUNT(*) INTO v_active_deals
  FROM trusted_partner_discounts
  WHERE trusted_partner_id = p_user_id
    AND is_active = true;

  -- Total Turnover (all completed deal authorizations)
  SELECT COALESCE(SUM(amount), 0) INTO v_total_turnover
  FROM deal_authorizations
  WHERE business_id = v_business_id
    AND status = 'completed';

  -- In-App Income
  SELECT COALESCE(SUM(amount), 0) INTO v_in_app_income
  FROM deal_authorizations
  WHERE business_id = v_business_id
    AND payment_method = 'in_app'
    AND status = 'completed';

  -- POS Income
  SELECT COALESCE(SUM(amount), 0) INTO v_pos_income
  FROM deal_authorizations
  WHERE business_id = v_business_id
    AND payment_method = 'pos'
    AND status = 'completed';

  -- Monthly Turnover (current month)
  SELECT COALESCE(SUM(amount), 0) INTO v_monthly_turnover
  FROM deal_authorizations
  WHERE business_id = v_business_id
    AND status = 'completed'
    AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', CURRENT_DATE);

  -- Weekly Turnover (last 7 days)
  SELECT COALESCE(SUM(amount), 0) INTO v_weekly_turnover
  FROM deal_authorizations
  WHERE business_id = v_business_id
    AND status = 'completed'
    AND created_at >= CURRENT_DATE - INTERVAL '7 days';

  -- Daily Turnover (today)
  SELECT COALESCE(SUM(amount), 0) INTO v_daily_turnover
  FROM deal_authorizations
  WHERE business_id = v_business_id
    AND status = 'completed'
    AND DATE(created_at) = CURRENT_DATE;

  -- Average Deal Value
  SELECT COALESCE(AVG(amount), 0) INTO v_avg_deal_value
  FROM deal_authorizations
  WHERE business_id = v_business_id
    AND status = 'completed';

  -- Completion Rate (completed / total requests)
  WITH totals AS (
    SELECT 
      COUNT(CASE WHEN status = 'completed' THEN 1 END) AS completed,
      COUNT(*) AS total
    FROM deal_authorizations
    WHERE business_id = v_business_id
      AND status IN ('approved', 'completed', 'rejected')
  )
  SELECT COALESCE(
    CASE 
      WHEN total > 0 THEN (completed::NUMERIC / total::NUMERIC) * 100 
      ELSE 0 
    END, 0
  ) INTO v_completion_rate
  FROM totals;

  -- Deal Request Counts by Status
  SELECT COUNT(*) INTO v_pending_requests
  FROM deal_authorizations
  WHERE business_id = v_business_id
    AND status = 'pending';

  SELECT COUNT(*) INTO v_approved_requests
  FROM deal_authorizations
  WHERE business_id = v_business_id
    AND status = 'approved';

  SELECT COUNT(*) INTO v_completed_deals
  FROM deal_authorizations
  WHERE business_id = v_business_id
    AND status = 'completed';

  SELECT COUNT(*) INTO v_rejected_requests
  FROM deal_authorizations
  WHERE business_id = v_business_id
    AND status = 'rejected';

  -- Unique Member Count (total unique customers)
  SELECT COUNT(DISTINCT member_id) INTO v_member_count
  FROM deal_authorizations
  WHERE business_id = v_business_id;

  -- Repeat Customer Count (members with 2+ completed deals)
  SELECT COUNT(*) INTO v_repeat_customer_count
  FROM (
    SELECT member_id
    FROM deal_authorizations
    WHERE business_id = v_business_id
      AND status = 'completed'
    GROUP BY member_id
    HAVING COUNT(*) >= 2
  ) AS repeat_customers;

  -- Top Performing Deals (by number of completions)
  SELECT json_agg(row_to_json(t))
  INTO v_top_deals
  FROM (
    SELECT 
      tpd.name AS deal_name,
      tpd.id AS deal_id,
      deal_stats.completion_count AS completions,
      deal_stats.total_revenue,
      deal_stats.avg_value
    FROM (
      SELECT 
        discount_id,
        COUNT(*) AS completion_count,
        SUM(amount) AS total_revenue,
        AVG(amount) AS avg_value
      FROM deal_authorizations
      WHERE business_id = v_business_id
        AND status = 'completed'
        AND discount_id IS NOT NULL
      GROUP BY discount_id
      ORDER BY completion_count DESC
      LIMIT 10
    ) AS deal_stats
    LEFT JOIN trusted_partner_discounts tpd ON tpd.id = deal_stats.discount_id
    ORDER BY deal_stats.completion_count DESC
  ) t;

  -- Recent Transactions (last 20)
  SELECT json_agg(row_to_json(t))
  INTO v_recent_transactions
  FROM (
    SELECT 
      da.id,
      da.amount,
      da.payment_method,
      da.status,
      da.created_at,
      COALESCE(p.name || ' ' || p.surname, 'Unknown') AS member_name,
      COALESCE(tpd.name, 'Unknown Deal') AS deal_name
    FROM deal_authorizations da
    LEFT JOIN profiles p ON da.member_id = p.id
    LEFT JOIN trusted_partner_discounts tpd ON da.discount_id = tpd.id
    WHERE da.business_id = v_business_id
    ORDER BY da.created_at DESC
    LIMIT 20
  ) t;

  -- Monthly Trends (last 12 months)
  SELECT json_agg(row_to_json(month_data))
  INTO v_monthly_trends
  FROM (
    SELECT 
      TO_CHAR(DATE_TRUNC('month', created_at), 'Mon YYYY') AS month,
      SUM(amount) AS revenue,
      COUNT(*) AS deal_count,
      SUM(CASE WHEN payment_method = 'in_app' THEN amount ELSE 0 END) AS in_app_revenue,
      SUM(CASE WHEN payment_method = 'pos' THEN amount ELSE 0 END) AS pos_revenue
    FROM deal_authorizations
    WHERE business_id = v_business_id
      AND status = 'completed'
      AND created_at >= CURRENT_DATE - INTERVAL '12 months'
    GROUP BY DATE_TRUNC('month', created_at)
    ORDER BY DATE_TRUNC('month', created_at) DESC
    LIMIT 12
  ) AS month_data;

  -- Payment Method Breakdown
  SELECT json_build_object(
    'in_app', json_build_object(
      'count', COALESCE(SUM(CASE WHEN payment_method = 'in_app' THEN 1 ELSE 0 END), 0),
      'revenue', COALESCE(SUM(CASE WHEN payment_method = 'in_app' THEN amount ELSE 0 END), 0)
    ),
    'pos', json_build_object(
      'count', COALESCE(SUM(CASE WHEN payment_method = 'pos' THEN 1 ELSE 0 END), 0),
      'revenue', COALESCE(SUM(CASE WHEN payment_method = 'pos' THEN amount ELSE 0 END), 0)
    )
  ) INTO v_payment_method_breakdown
  FROM deal_authorizations
  WHERE business_id = v_business_id
    AND status = 'completed';

  -- Deal Status Breakdown
  SELECT json_build_object(
    'pending', v_pending_requests,
    'approved', v_approved_requests,
    'completed', v_completed_deals,
    'rejected', v_rejected_requests
  ) INTO v_deal_status_breakdown;

  -- Build final result
  result := json_build_object(
    'overview', json_build_object(
      'total_deals_created', v_total_deals_created,
      'active_deals', v_active_deals,
      'total_turnover', v_total_turnover,
      'in_app_income', v_in_app_income,
      'pos_income', v_pos_income,
      'monthly_turnover', v_monthly_turnover,
      'weekly_turnover', v_weekly_turnover,
      'daily_turnover', v_daily_turnover,
      'avg_deal_value', v_avg_deal_value,
      'completion_rate', v_completion_rate,
      'total_customers', v_member_count,
      'repeat_customers', v_repeat_customer_count
    ),
    'deal_status', v_deal_status_breakdown,
    'payment_methods', v_payment_method_breakdown,
    'top_deals', COALESCE(v_top_deals, '[]'::json),
    'recent_transactions', COALESCE(v_recent_transactions, '[]'::json),
    'monthly_trends', COALESCE(v_monthly_trends, '[]'::json)
  );

  RETURN result;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_trusted_partner_analytics(UUID) TO authenticated;

-- Test query (run this to verify function works)
-- SELECT get_trusted_partner_analytics(auth.uid());
