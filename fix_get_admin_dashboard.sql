-- Fix get_admin_dashboard RPC function
-- Issues fixed:
--   - payments.member_id does not exist (column is user_id)
--   - profiles.category used for category_summary but it's not meaningful for revenue
--   - in_store_purchases was always 0 – now sums approved deal_authorizations
--   - Deactivated profiles are now excluded from counts
--
-- Run this in the Supabase SQL editor.

DROP FUNCTION IF EXISTS public.get_admin_dashboard();

CREATE OR REPLACE FUNCTION public.get_admin_dashboard()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result json;
BEGIN
  SELECT json_build_object(
    'total_members',
      (SELECT count(*) FROM profiles
       WHERE role = 'member' AND (is_deactivated IS NULL OR is_deactivated = false)),
    'total_trusted_partners',
      (SELECT count(*) FROM profiles
       WHERE role = 'trusted_partner' AND (is_deactivated IS NULL OR is_deactivated = false)),
    'total_online_purchases',
      COALESCE(
        (SELECT sum(amount) FROM payments WHERE status = 'completed'),
        0
      ),
    'total_in_store_purchases',
      COALESCE(
        (SELECT sum(COALESCE(
          (bill_data->>'original_bill_amount')::numeric,
          amount,
          0
        ))
        FROM deal_authorizations WHERE status = 'approved'),
        0
      ),
    'category_summary',
      COALESCE(
        (SELECT json_agg(row_to_json(cs))
         FROM (
           SELECT b.category,
                  count(*) AS total_count,
                  COALESCE(sum(COALESCE(
                    (da.bill_data->>'original_bill_amount')::numeric,
                    da.amount,
                    0
                  )), 0) AS total_amount
           FROM deal_authorizations da
           JOIN businesses b ON b.id = da.trusted_partner_id
           WHERE da.status = 'approved'
             AND b.category IS NOT NULL
           GROUP BY b.category
         ) cs),
        '[]'::json
      ),
    'category_details',
      '{}'::json
  ) INTO result;

  RETURN result;
END;
$$;

-- Also create the secure variant that the app tries first
DROP FUNCTION IF EXISTS public.secure_get_admin_dashboard();

CREATE OR REPLACE FUNCTION public.secure_get_admin_dashboard()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.get_admin_dashboard();
END;
$$;
