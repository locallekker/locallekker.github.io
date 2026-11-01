-- Create function to get top members by total spending
CREATE OR REPLACE FUNCTION get_top_members(member_limit INT DEFAULT 10)
RETURNS TABLE (
  member_id UUID,
  member_name TEXT,
  total_spent NUMERIC,
  total_transactions BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    da.member_id,
    CONCAT(p.name, ' ', p.surname) as member_name,
    SUM(da.amount) as total_spent,
    COUNT(*) as total_transactions
  FROM deal_authorizations da
  LEFT JOIN profiles p ON da.member_id = p.id
  WHERE da.status = 'completed'
    AND da.amount IS NOT NULL
  GROUP BY da.member_id, p.name, p.surname
  HAVING COUNT(*) > 0
  ORDER BY total_spent DESC
  LIMIT member_limit;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_top_members(INT) TO authenticated;

-- Add comment
COMMENT ON FUNCTION get_top_members(INT) IS 'Returns top members ranked by total spending from completed deal authorizations';
