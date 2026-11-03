BEGIN;

-- Anonymous, device-scoped browsing analytics. Guest ids are random UUIDs
-- generated on the device; no personal data is stored until the guest signs
-- in, at which point the device's guest id is linked to their account.
CREATE TABLE IF NOT EXISTS public.guest_visitors (
  guest_id UUID PRIMARY KEY,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  converted_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  converted_at TIMESTAMPTZ,
  conversion_type TEXT CHECK (conversion_type IN ('signup', 'signin'))
);

CREATE TABLE IF NOT EXISTS public.guest_deal_request_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  guest_id UUID NOT NULL REFERENCES public.guest_visitors(guest_id) ON DELETE CASCADE,
  discount_id UUID REFERENCES public.trusted_partner_discounts(id) ON DELETE SET NULL,
  deal_name TEXT,
  business_id UUID,
  potential_savings NUMERIC(12, 2),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS guest_visitors_last_seen_idx
  ON public.guest_visitors (last_seen_at);
CREATE INDEX IF NOT EXISTS guest_visitors_converted_user_idx
  ON public.guest_visitors (converted_user_id);
CREATE INDEX IF NOT EXISTS guest_deal_request_attempts_created_idx
  ON public.guest_deal_request_attempts (created_at);
CREATE INDEX IF NOT EXISTS guest_deal_request_attempts_guest_idx
  ON public.guest_deal_request_attempts (guest_id, created_at);

-- Only the SECURITY DEFINER functions below may read or write these tables.
ALTER TABLE public.guest_visitors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guest_deal_request_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.guest_visitors FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.guest_deal_request_attempts FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.record_guest_visit(p_guest_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL OR p_guest_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.guest_visitors (guest_id)
  VALUES (p_guest_id)
  ON CONFLICT (guest_id) DO UPDATE
    SET last_seen_at = now()
    WHERE guest_visitors.converted_user_id IS NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_guest_deal_request(
  p_guest_id UUID,
  p_discount_id UUID,
  p_potential_savings NUMERIC DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deal RECORD;
  v_savings NUMERIC;
BEGIN
  IF auth.uid() IS NOT NULL OR p_guest_id IS NULL OR p_discount_id IS NULL THEN
    RETURN;
  END IF;

  SELECT d.id, d.name, coalesce(d.business_id, b.id) AS business_id
  INTO v_deal
  FROM public.trusted_partner_discounts d
  LEFT JOIN public.businesses b ON b.owner_member_id = d.trusted_partner_id
  WHERE d.id = p_discount_id AND d.is_active = true
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  INSERT INTO public.guest_visitors (guest_id)
  VALUES (p_guest_id)
  ON CONFLICT (guest_id) DO UPDATE
    SET last_seen_at = now()
    WHERE guest_visitors.converted_user_id IS NULL;

  -- Ignore double taps and cap noisy devices so analytics stay meaningful.
  IF EXISTS (
    SELECT 1 FROM public.guest_deal_request_attempts
    WHERE guest_id = p_guest_id
      AND discount_id = p_discount_id
      AND created_at > now() - INTERVAL '30 seconds'
  ) OR (
    SELECT count(*) FROM public.guest_deal_request_attempts
    WHERE guest_id = p_guest_id AND created_at > now() - INTERVAL '1 hour'
  ) >= 30 THEN
    RETURN;
  END IF;

  v_savings := CASE
    WHEN p_potential_savings IS NULL
      OR p_potential_savings < 0
      OR p_potential_savings > 100000 THEN NULL
    ELSE round(p_potential_savings, 2)
  END;

  INSERT INTO public.guest_deal_request_attempts (
    guest_id, discount_id, deal_name, business_id, potential_savings
  ) VALUES (
    p_guest_id, v_deal.id, v_deal.name, v_deal.business_id, v_savings
  );
END;
$$;

-- Called after sign-in/sign-up. A guest id converts once, to the first
-- account that claims it. New accounts created after the guest first browsed
-- count as signups; older accounts count as existing members signing in.
CREATE OR REPLACE FUNCTION public.link_guest_conversion(p_guest_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_user_created TIMESTAMPTZ;
  v_type TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_guest_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT created_at INTO v_user_created FROM auth.users WHERE id = v_user_id;

  UPDATE public.guest_visitors
  SET converted_user_id = v_user_id,
      converted_at = now(),
      conversion_type = CASE
        WHEN v_user_created IS NOT NULL AND v_user_created >= first_seen_at
          THEN 'signup'
        ELSE 'signin'
      END
  WHERE guest_id = p_guest_id AND converted_user_id IS NULL
  RETURNING conversion_type INTO v_type;

  RETURN v_type;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_admin_guest_conversion_report(
  p_start TIMESTAMPTZ,
  p_end TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_start IS NULL OR p_end IS NULL OR p_start >= p_end
     OR p_end - p_start > INTERVAL '366 days' THEN
    RAISE EXCEPTION 'Invalid reporting period' USING ERRCODE = '22023';
  END IF;

  WITH visitors AS (
    SELECT * FROM public.guest_visitors
    WHERE first_seen_at < p_end AND last_seen_at >= p_start
  ),
  attempts AS (
    SELECT a.*, v.converted_user_id, v.conversion_type
    FROM public.guest_deal_request_attempts a
    JOIN public.guest_visitors v USING (guest_id)
    WHERE a.created_at >= p_start AND a.created_at < p_end
  ),
  requesting AS (
    SELECT DISTINCT guest_id, converted_user_id, conversion_type FROM attempts
  ),
  deal_totals AS (
    SELECT
      a.discount_id,
      max(a.deal_name) AS deal_name,
      max(a.business_id::TEXT)::UUID AS business_id,
      count(*) AS attempts,
      count(DISTINCT a.guest_id) AS guests,
      count(DISTINCT a.guest_id) FILTER (WHERE a.converted_user_id IS NOT NULL)
        AS converted_guests,
      coalesce(sum(a.potential_savings), 0) AS potential_savings
    FROM attempts a
    GROUP BY a.discount_id
  ),
  deals AS (
    SELECT
      t.discount_id,
      coalesce(d.name, t.deal_name, 'Removed deal') AS deal_name,
      (SELECT b.name FROM public.businesses b
       WHERE b.id = coalesce(t.business_id, d.business_id)
          OR (t.business_id IS NULL AND b.owner_member_id = d.trusted_partner_id)
       LIMIT 1) AS business_name,
      t.attempts,
      t.guests,
      t.converted_guests,
      t.potential_savings
    FROM deal_totals t
    LEFT JOIN public.trusted_partner_discounts d ON d.id = t.discount_id
  )
  SELECT jsonb_build_object(
    'period_start', p_start,
    'period_end', p_end,
    'browsing_guests', (SELECT count(*) FROM visitors),
    'converted_browsing_guests',
      (SELECT count(*) FROM visitors WHERE converted_user_id IS NOT NULL),
    'requesting_guests', (SELECT count(*) FROM requesting),
    'request_attempts', (SELECT count(*) FROM attempts),
    'converted_requesting_guests',
      (SELECT count(*) FROM requesting WHERE converted_user_id IS NOT NULL),
    'signup_conversions',
      (SELECT count(*) FROM requesting WHERE conversion_type = 'signup'),
    'signin_conversions',
      (SELECT count(*) FROM requesting WHERE conversion_type = 'signin'),
    'potential_savings_total',
      (SELECT coalesce(sum(potential_savings), 0) FROM attempts),
    'deals', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'discount_id', discount_id,
        'deal_name', deal_name,
        'business_name', business_name,
        'attempts', attempts,
        'guests', guests,
        'converted_guests', converted_guests,
        'potential_savings', potential_savings
      ) ORDER BY attempts DESC, guests DESC, deal_name)
      FROM (SELECT * FROM deals ORDER BY attempts DESC LIMIT 100) top_deals
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.record_guest_visit(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_guest_deal_request(UUID, UUID, NUMERIC) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.link_guest_conversion(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_admin_guest_conversion_report(TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_guest_visit(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_guest_deal_request(UUID, UUID, NUMERIC) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.link_guest_conversion(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_guest_conversion_report(TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;

COMMIT;
