-- Create function to get top deals with sales reports
CREATE OR REPLACE FUNCTION get_top_deals(deal_limit INT DEFAULT 100)
RETURNS TABLE (
    deal_id TEXT,
    deal_name TEXT,
    business_id TEXT,
    business_name TEXT,
    in_app_revenue NUMERIC,
    in_store_revenue NUMERIC,
    total_sales BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        tpd.id::TEXT AS deal_id,
        tpd.name AS deal_name,
        b.id::TEXT AS business_id,
        b.name AS business_name,
        COALESCE(SUM(CASE WHEN da.payment_method = 'in_app' THEN da.amount ELSE 0 END), 0)::NUMERIC AS in_app_revenue,
        COALESCE(SUM(CASE WHEN da.payment_method = 'pos' THEN da.amount ELSE 0 END), 0)::NUMERIC AS in_store_revenue,
        COUNT(da.id) AS total_sales
    FROM trusted_partner_discounts tpd
    LEFT JOIN deal_authorizations da ON tpd.id = da.discount_id AND da.status IN ('approved', 'completed')
    LEFT JOIN businesses b ON tpd.business_id = b.id
    WHERE tpd.is_active = true
    GROUP BY tpd.id, tpd.name, b.id, b.name
    HAVING COUNT(da.id) > 0
    ORDER BY (COALESCE(SUM(da.amount), 0)) DESC
    LIMIT deal_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_top_deals(INT) TO authenticated;
