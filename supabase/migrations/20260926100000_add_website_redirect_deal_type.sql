-- Website-redirect deals: admin-only deal type that sends members to the
-- trusted partner's website (businesses.website_url), plus click tracking.
-- Safe to run multiple times.

BEGIN;

-- ---------------------------------------------------------------------------
-- Admin check usable from triggers/policies without RLS recursion.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    EXISTS (
      SELECT 1 FROM public.memberships m
      WHERE m.user_id = auth.uid() AND lower(m.role) = 'admin'
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND lower(p.role) = 'admin'
    )
    OR lower(coalesce(auth.jwt() ->> 'email', '')) IN (
      'locallekkerclub@gmail.com', 'admin@locallekker.com'
    )
    OR lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'admin'
    OR lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'user_type', '')) = 'admin';
$$;

REVOKE ALL ON FUNCTION public.is_platform_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated;

-- ---------------------------------------------------------------------------
-- Only admins may create, change or delete website_redirect deals.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_website_redirect_deal_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request_role TEXT := coalesce(auth.jwt() ->> 'role', '');
  v_touches_redirect BOOLEAN := FALSE;
  v_becomes_redirect BOOLEAN := FALSE;
  v_website TEXT;
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    IF OLD.deal_type = 'website_redirect' THEN
      v_touches_redirect := TRUE;
    END IF;
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    IF NEW.deal_type = 'website_redirect' THEN
      v_touches_redirect := TRUE;
      IF TG_OP = 'INSERT' THEN
        v_becomes_redirect := TRUE;
      ELSE
        v_becomes_redirect := OLD.deal_type IS DISTINCT FROM 'website_redirect';
      END IF;
    END IF;
  END IF;

  IF NOT v_touches_redirect THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
  END IF;

  -- service_role / SQL editor requests are trusted; app users must be admins.
  IF v_request_role IN ('anon', 'authenticated') AND NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Only Local Lekker admins can manage website redirect deals'
      USING ERRCODE = '42501';
  END IF;

  IF v_becomes_redirect THEN
    SELECT b.website_url INTO v_website
    FROM public.businesses b
    WHERE b.owner_member_id = NEW.trusted_partner_id
    LIMIT 1;

    IF v_website IS NULL
       OR btrim(v_website) !~* '^(https?://)?([a-z0-9-]+\.)+[a-z]{2,}(:[0-9]{1,5})?(/[^[:space:]]*)?$' THEN
      RAISE EXCEPTION 'Trusted partner needs a valid website URL before a website redirect deal can be created'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_website_redirect_deal_rules
  ON public.trusted_partner_discounts;

CREATE TRIGGER trg_enforce_website_redirect_deal_rules
  BEFORE INSERT OR UPDATE OR DELETE ON public.trusted_partner_discounts
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_website_redirect_deal_rules();

-- ---------------------------------------------------------------------------
-- Click tracking for referral reporting.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.deal_redirect_clicks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  deal_id UUID NOT NULL
    REFERENCES public.trusted_partner_discounts(id) ON DELETE CASCADE,
  trusted_partner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  member_id UUID NOT NULL DEFAULT auth.uid()
    REFERENCES auth.users(id) ON DELETE CASCADE,
  clicked_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_deal_redirect_clicks_deal_id
  ON public.deal_redirect_clicks(deal_id);
CREATE INDEX IF NOT EXISTS idx_deal_redirect_clicks_partner_time
  ON public.deal_redirect_clicks(trusted_partner_id, clicked_at DESC);

ALTER TABLE public.deal_redirect_clicks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can log their own redirect clicks"
  ON public.deal_redirect_clicks;
CREATE POLICY "Members can log their own redirect clicks"
  ON public.deal_redirect_clicks
  FOR INSERT TO authenticated
  WITH CHECK (
    member_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.trusted_partner_discounts d
      WHERE d.id = deal_redirect_clicks.deal_id
        AND d.deal_type = 'website_redirect'
        AND d.is_active = TRUE
        AND d.trusted_partner_id IS NOT DISTINCT FROM deal_redirect_clicks.trusted_partner_id
    )
  );

DROP POLICY IF EXISTS "Admins can view redirect clicks"
  ON public.deal_redirect_clicks;
CREATE POLICY "Admins can view redirect clicks"
  ON public.deal_redirect_clicks
  FOR SELECT TO authenticated
  USING (public.is_platform_admin());

GRANT SELECT, INSERT ON public.deal_redirect_clicks TO authenticated;

-- Per-deal click totals; SECURITY INVOKER so RLS limits results to admins.
CREATE OR REPLACE FUNCTION public.get_deal_redirect_click_counts(p_deal_ids UUID[])
RETURNS TABLE (deal_id UUID, click_count BIGINT)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT c.deal_id, count(*)::BIGINT
  FROM public.deal_redirect_clicks c
  WHERE c.deal_id = ANY(p_deal_ids)
  GROUP BY c.deal_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_deal_redirect_click_counts(UUID[]) TO authenticated;

COMMIT;
