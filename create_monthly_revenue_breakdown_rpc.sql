-- Create RPC function to get monthly revenue breakdown with payment methods
-- This will be used by the monthly revenue report page

DROP FUNCTION IF EXISTS public.get_monthly_revenue_breakdown();

CREATE OR REPLACE FUNCTION public.get_monthly_revenue_breakdown()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSON;
BEGIN
  -- Get all months with revenue broken down by payment method
  SELECT JSON_AGG(
    JSON_BUILD_OBJECT(
      'month', month,
      'total_revenue', total_revenue,
      'in_app_revenue', in_app_revenue,
      'pos_revenue', pos_revenue,
      'transactions', transactions
    ) ORDER BY month DESC
  ) INTO result
  FROM (
    SELECT 
      TO_CHAR(DATE_TRUNC('month', created_at), 'YYYY-MM') as month,
      SUM(amount) as total_revenue,
      SUM(CASE WHEN payment_method = 'in_app' THEN amount ELSE 0 END) as in_app_revenue,
      SUM(CASE WHEN payment_method = 'pos' THEN amount ELSE 0 END) as pos_revenue,
      COUNT(*) as transactions
    FROM deal_authorizations
    WHERE status = 'completed'
      AND amount IS NOT NULL
    GROUP BY DATE_TRUNC('month', created_at)
    ORDER BY DATE_TRUNC('month', created_at) DESC
  ) monthly_breakdown;

  RETURN COALESCE(result, '[]'::JSON);
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.get_monthly_revenue_breakdown() TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.get_monthly_revenue_breakdown() IS 
'Returns monthly revenue breakdown including payment method splits for approved/completed deals';
