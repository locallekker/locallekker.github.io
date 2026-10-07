-- Repair installations whose payments table has completed_at but no happened_at.
-- Replaces only the report RPC; does not recreate tables or modify payment data.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_admin_engagement_report(
  p_start TIMESTAMPTZ, p_end TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_start IS NULL OR p_end IS NULL OR p_start >= p_end THEN
    RAISE EXCEPTION 'Invalid reporting period' USING ERRCODE = '22023';
  END IF;

  WITH
  deals AS (
    SELECT d.*, coalesce(d.trusted_partner_id, b.owner_member_id) AS partner_id
    FROM public.trusted_partner_discounts d
    LEFT JOIN public.businesses b ON b.id = d.business_id
  ),
  views AS (
    SELECT v.*, d.partner_id
    FROM public.deal_detail_views v JOIN deals d ON d.id = v.deal_id
    WHERE v.viewed_at >= p_start AND v.viewed_at < p_end
  ),
  clicks AS (
    SELECT c.*, d.partner_id
    FROM public.deal_redirect_clicks c JOIN deals d ON d.id = c.deal_id
    WHERE c.clicked_at >= p_start AND c.clicked_at < p_end
      AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = c.member_id AND p.role = 'member')
  ),
  transactions AS (
    SELECT a.*,
      coalesce(d.partner_id, b.owner_member_id, a.trusted_partner_id) AS partner_id,
      coalesce(
        a.completed_at,
        nullif(to_jsonb(a)->>'payment_completed_at', '')::TIMESTAMPTZ,
        a.updated_at, a.created_at
      ) AS sale_at
    FROM public.deal_authorizations a
    LEFT JOIN deals d ON d.id = a.discount_id
    LEFT JOIN public.businesses b ON b.id = coalesce(a.business_id, a.trusted_partner_id)
  ),
  sales AS (
    SELECT * FROM transactions
    WHERE status = 'completed' AND sale_at >= p_start AND sale_at < p_end
  ),
  requests AS (
    SELECT * FROM transactions WHERE created_at >= p_start AND created_at < p_end
  ),
  payments AS (
    SELECT p.* FROM public.payments p
    WHERE p.status = 'completed'
      AND coalesce(
        nullif(to_jsonb(p)->>'completed_at', '')::TIMESTAMPTZ,
        nullif(to_jsonb(p)->>'happened_at', '')::TIMESTAMPTZ, p.created_at
      ) >= p_start
      AND coalesce(
        nullif(to_jsonb(p)->>'completed_at', '')::TIMESTAMPTZ,
        nullif(to_jsonb(p)->>'happened_at', '')::TIMESTAMPTZ, p.created_at
      ) < p_end
  ),
  signups AS (
    SELECT * FROM public.profiles
    WHERE created_at >= p_start AND created_at < p_end
  ),
  deal_stats AS (
    SELECT d.id, d.partner_id, d.name, to_jsonb(d)->>'deal_type' AS deal_type, d.is_active,
      (SELECT count(*) FROM views v WHERE v.deal_id = d.id) AS views,
      (SELECT count(DISTINCT member_id) FROM views v WHERE v.deal_id = d.id) AS viewers,
      (SELECT count(*) FROM clicks c WHERE c.deal_id = d.id) AS redirect_clicks,
      (SELECT count(*) FROM requests r WHERE r.discount_id = d.id) AS requests,
      (SELECT count(*) FROM requests r WHERE r.discount_id = d.id AND r.status = 'pending') AS pending,
      (SELECT count(*) FROM requests r WHERE r.discount_id = d.id AND r.status = 'approved') AS approved,
      (SELECT count(*) FROM requests r WHERE r.discount_id = d.id AND r.status = 'rejected') AS rejected,
      (SELECT count(*) FROM sales s WHERE s.discount_id = d.id) AS redemptions,
      (SELECT count(DISTINCT member_id) FROM sales s WHERE s.discount_id = d.id) AS redeeming_members,
      (SELECT coalesce(sum(amount), 0) FROM sales s WHERE s.discount_id = d.id) AS sales,
      (SELECT count(*) FROM sales s WHERE s.discount_id = d.id AND s.amount IS NULL) AS missing_amounts
    FROM deals d
  ),
  partner_stats AS (
    SELECT p.id AS partner_id,
      coalesce(b.name, nullif(concat_ws(' ', p.name, p.surname), ''), 'Unnamed partner') AS name,
      coalesce(to_jsonb(b)->>'city', p.city, '') AS city,
      coalesce(b.contact_email, p.email, '') AS email,
      coalesce(b.contact_number, p.contact, '') AS contact,
      (SELECT count(*) FROM views v WHERE v.partner_id = p.id) AS views,
      (SELECT count(DISTINCT member_id) FROM views v WHERE v.partner_id = p.id) AS viewers,
      (SELECT count(*) FROM clicks c WHERE c.partner_id = p.id) AS redirect_clicks,
      (SELECT count(*) FROM requests r WHERE r.partner_id = p.id) AS requests,
      (SELECT count(*) FROM sales s WHERE s.partner_id = p.id) AS redemptions,
      (SELECT coalesce(sum(amount), 0) FROM sales s WHERE s.partner_id = p.id) AS sales,
      (SELECT count(*) FROM sales s WHERE s.partner_id = p.id AND s.amount IS NULL) AS missing_amounts,
      coalesce((SELECT jsonb_agg(to_jsonb(ds) ORDER BY ds.views, ds.name)
        FROM deal_stats ds WHERE ds.partner_id = p.id), '[]'::JSONB) AS deals
    FROM public.profiles p
    LEFT JOIN public.businesses b ON b.owner_member_id = p.id
    WHERE p.role = 'trusted_partner'
  )
  SELECT jsonb_build_object(
    'tracking_started_at', (SELECT tracking_started_at FROM public.admin_analytics_metadata WHERE singleton),
    'member_signups', (SELECT count(*) FROM signups WHERE role = 'member'),
    'partner_signups', (SELECT count(*) FROM signups WHERE role = 'trusted_partner'),
    'active_member_signups', (SELECT count(*) FROM signups s
      WHERE role = 'member' AND subscription = 'active'
        AND (to_jsonb(s)->>'is_deactivated')::BOOLEAN IS NOT TRUE),
    'ready_partner_signups', CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'partner_terms_accepted'
    ) THEN (SELECT count(*) FROM signups s WHERE role = 'trusted_partner'
      AND (to_jsonb(s)->>'partner_terms_accepted')::BOOLEAN = TRUE
      AND (to_jsonb(s)->>'is_deactivated')::BOOLEAN IS NOT TRUE) ELSE NULL END,
    'subscription_payments', (SELECT count(*) FROM payments),
    'subscription_sales', (SELECT coalesce(sum(amount), 0) FROM payments),
    'redemptions', (SELECT count(*) FROM sales),
    'deal_sales', (SELECT coalesce(sum(amount), 0) FROM sales),
    'in_app_sales', (SELECT coalesce(sum(amount), 0) FROM sales WHERE payment_method = 'in_app'),
    'pos_sales', (SELECT coalesce(sum(amount), 0) FROM sales WHERE payment_method = 'pos'),
    'other_sales', (SELECT coalesce(sum(amount), 0) FROM sales WHERE payment_method IS NULL OR payment_method NOT IN ('in_app', 'pos')),
    'missing_amounts', (SELECT count(*) FROM sales WHERE amount IS NULL),
    'views', (SELECT count(*) FROM views),
    'viewers', (SELECT count(DISTINCT member_id) FROM views),
    'partners', coalesce((SELECT jsonb_agg(to_jsonb(ps) ORDER BY ps.views, ps.name) FROM partner_stats ps), '[]'::JSONB)
  ) INTO v_result;
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.get_admin_engagement_report(TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_engagement_report(TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;

COMMIT;
