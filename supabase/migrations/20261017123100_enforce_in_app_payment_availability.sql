-- Server-side enforcement for the in-app payment availability guard.
-- Apply ONLY when the app version containing the guard UI is live on the
-- Play Store: older app versions will then get an error (instead of the later
-- "banking setup" message) when choosing in-app payment for a partner without
-- banking details. Requires 20261017123000. Safe to run multiple times.

BEGIN;

-- Server-side backstop: reject new in-app deal requests for partners without
-- a payout account (covers outdated app versions). service_role is trusted.
CREATE OR REPLACE FUNCTION public.enforce_in_app_payment_availability()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request_role TEXT := coalesce(auth.jwt() ->> 'role', '');
BEGIN
  IF NEW.payment_method = 'in_app'
     AND NEW.discount_id IS NOT NULL
     AND v_request_role IN ('anon', 'authenticated')
     AND NOT public.discount_accepts_in_app_payment(NEW.discount_id) THEN
    RAISE EXCEPTION 'IN_APP_PAYMENT_UNAVAILABLE: This partner cannot accept in-app payments yet. Please choose Pay in store.'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_in_app_payment_availability
  ON public.deal_authorizations;

CREATE TRIGGER trg_enforce_in_app_payment_availability
  BEFORE INSERT ON public.deal_authorizations
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_in_app_payment_availability();

COMMIT;
