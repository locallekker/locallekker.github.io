-- Create RPC function to get all deal authorizations for admin
DROP FUNCTION IF EXISTS public.get_all_deal_authorizations();

CREATE OR REPLACE FUNCTION public.get_all_deal_authorizations()
RETURNS TABLE (
  id UUID,
  member_id UUID,
  business_id UUID,
  discount_id UUID,
  amount NUMERIC,
  status TEXT,
  payment_method TEXT,
  created_at TIMESTAMPTZ,
  member_name TEXT,
  business_name TEXT,
  discount_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    da.id,
    da.member_id,
    da.business_id,
    da.discount_id,
    da.amount,
    da.status,
    da.payment_method,
    da.created_at,
    CONCAT(p.name, ' ', p.surname) as member_name,
    b.name as business_name,
    tpd.name as discount_name
  FROM deal_authorizations da
  LEFT JOIN profiles p ON da.member_id = p.id
  LEFT JOIN businesses b ON da.business_id = b.id
  LEFT JOIN trusted_partner_discounts tpd ON da.discount_id = tpd.id
  ORDER BY da.created_at DESC;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.get_all_deal_authorizations() TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.get_all_deal_authorizations() IS 
'Returns all deal authorizations with member, business, and discount names for admin dashboard';
