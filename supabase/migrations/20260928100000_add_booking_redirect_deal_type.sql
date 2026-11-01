-- Booking-redirect deals: admin-only deal type (Locally Active category only)
-- that sends members to an external booking page (e.g. Playtomic) stored in
-- custom_data->>'booking_url'. Reuses deal_redirect_clicks/
-- get_deal_redirect_click_counts from the website_redirect migration.
-- Safe to run multiple times.

BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_booking_redirect_deal_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request_role TEXT := coalesce(auth.jwt() ->> 'role', '');
  v_touches_booking BOOLEAN := FALSE;
  v_becomes_booking BOOLEAN := FALSE;
  v_booking_url TEXT;
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    IF OLD.deal_type = 'booking_redirect' THEN
      v_touches_booking := TRUE;
    END IF;
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    IF NEW.deal_type = 'booking_redirect' THEN
      v_touches_booking := TRUE;
      IF TG_OP = 'INSERT' THEN
        v_becomes_booking := TRUE;
      ELSE
        v_becomes_booking := OLD.deal_type IS DISTINCT FROM 'booking_redirect';
      END IF;
    END IF;
  END IF;

  IF NOT v_touches_booking THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
  END IF;

  -- service_role / SQL editor requests are trusted; app users must be admins.
  IF v_request_role IN ('anon', 'authenticated') AND NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Only Local Lekker admins can manage booking redirect deals'
      USING ERRCODE = '42501';
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.deal_type = 'booking_redirect' THEN
    IF NEW.deal_category IS DISTINCT FROM 'Locally Active' THEN
      RAISE EXCEPTION 'Booking redirect deals are only allowed in the Locally Active category'
        USING ERRCODE = '23514';
    END IF;

    v_booking_url := btrim(coalesce(NEW.custom_data ->> 'booking_url', ''));
    IF v_booking_url = ''
       OR v_booking_url !~* '^(https?://)?([a-z0-9-]+\.)+[a-z]{2,}(:[0-9]{1,5})?(/[^[:space:]]*)?$' THEN
      RAISE EXCEPTION 'A valid booking URL is required for booking redirect deals'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_booking_redirect_deal_rules
  ON public.trusted_partner_discounts;

CREATE TRIGGER trg_enforce_booking_redirect_deal_rules
  BEFORE INSERT OR UPDATE OR DELETE ON public.trusted_partner_discounts
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_booking_redirect_deal_rules();

-- Allow booking_redirect clicks to be logged via the shared clicks table.
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
        AND d.deal_type IN ('website_redirect', 'booking_redirect')
        AND d.is_active = TRUE
        AND d.trusted_partner_id IS NOT DISTINCT FROM deal_redirect_clicks.trusted_partner_id
    )
  );

COMMIT;
