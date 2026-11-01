-- Create RPC function to get all transactions for a specific business
-- This bypasses RLS policies using SECURITY DEFINER

CREATE OR REPLACE FUNCTION get_business_transactions(p_business_id UUID)
RETURNS TABLE (
  id UUID,
  amount NUMERIC,
  payment_method TEXT,
  created_at TIMESTAMPTZ,
  status TEXT,
  member_id UUID,
  member_name TEXT,
  member_surname TEXT,
  discount_name TEXT
) 
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    da.id,
    da.amount,
    da.payment_method,
    da.created_at,
    da.status,
    da.member_id,
    p.name AS member_name,
    p.surname AS member_surname,
    tpd.name AS discount_name
  FROM deal_authorizations da
  LEFT JOIN profiles p ON da.member_id = p.id
  LEFT JOIN trusted_partner_discounts tpd ON da.discount_id = tpd.id
  WHERE da.business_id = p_business_id
  ORDER BY da.created_at DESC;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_business_transactions(UUID) TO authenticated;
