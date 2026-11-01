-- ============================================================
-- Member Email Triggers
-- ============================================================
-- Ensures ALL members receive:
--   1. A deal-request confirmation email when they submit a deal request
--   2. A payment-success email when their in-app payment is confirmed
--
-- Uses pg_net to call two Supabase Edge Functions from the database,
-- so emails are sent even if the app code path is incomplete (e.g. app
-- crash, old app version, background webhook recovery).
--
-- Prerequisites
-- -------------
-- 1. pg_net extension must be enabled:
--      Dashboard → Database → Extensions → pg_net  (enable)
--
-- 2. Store the service-role key as a database setting so the trigger
--    can attach it as an Authorization header:
--
--      ALTER DATABASE postgres
--        SET "app.settings.service_role_key" = '<YOUR_SERVICE_ROLE_KEY>';
--
--    (Run once; only needs to be repeated if the key rotates.)
--    The key is visible in: Supabase Dashboard → Project Settings → API
--
-- 3. Deploy the two new Edge Functions before running this script:
--      supabase functions deploy send-member-deal-request-confirmation-email
--      supabase functions deploy send-member-payment-success-email
-- ============================================================

-- Enable pg_net (idempotent)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ============================================================
-- TRIGGER 1 – Deal request confirmation → member
-- Fires on every INSERT into deal_authorizations.
-- Looks up member name + email, business name, and deal name,
-- then calls the confirmation edge function.
-- ============================================================

CREATE OR REPLACE FUNCTION public.trigger_member_deal_request_confirmation_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_supabase_url    TEXT;
  v_service_key     TEXT;
  v_edge_url        TEXT;
  v_member_email    TEXT;
  v_member_name     TEXT;
  v_business_name   TEXT;
  v_deal_name       TEXT;
BEGIN
  -- Read project settings (set via ALTER DATABASE ... SET ...)
  v_supabase_url := coalesce(
    current_setting('app.settings.supabase_url', true),
    'https://qdrotavcmmevhgveodcp.supabase.co'
  );
  v_service_key := current_setting('app.settings.service_role_key', true);

  -- Skip silently if the key is not configured yet
  IF v_service_key IS NULL OR v_service_key = '' THEN
    RAISE WARNING 'trigger_member_deal_request_confirmation_email: service_role_key not set – skipping';
    RETURN NEW;
  END IF;

  v_edge_url := v_supabase_url || '/functions/v1/send-member-deal-request-confirmation-email';

  -- Resolve member email + display name
  SELECT p.email,
         trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, ''))
  INTO   v_member_email, v_member_name
  FROM   public.profiles p
  WHERE  p.id = NEW.member_id;

  -- Skip if no email on record (anonymous or incomplete profile)
  IF v_member_email IS NULL THEN
    RETURN NEW;
  END IF;

  -- Resolve business display name
  SELECT b.name
  INTO   v_business_name
  FROM   public.businesses b
  WHERE  b.id = NEW.business_id;

  -- Resolve deal name from the snapshot (fast, no join) or from the discounts table
  IF NEW.deal_snapshot IS NOT NULL AND NEW.deal_snapshot->>'name' IS NOT NULL THEN
    v_deal_name := NEW.deal_snapshot->>'name';
  ELSE
    SELECT d.name
    INTO   v_deal_name
    FROM   public.trusted_partner_discounts d
    WHERE  d.id = NEW.discount_id;
  END IF;

  -- Fire-and-forget HTTP call via pg_net
  PERFORM extensions.net.http_post(
    url     := v_edge_url,
    body    := jsonb_build_object(
                 'member_id',              NEW.member_id,
                 'member_email',           v_member_email,
                 'member_name',            v_member_name,
                 'business_name',          v_business_name,
                 'deal_name',              v_deal_name,
                 'amount',                 NEW.amount,
                 'payment_method',         NEW.payment_method,
                 'quantity',               NEW.quantity,
                 'deal_authorization_id',  NEW.id
               ),
    headers := jsonb_build_object(
                 'Content-Type',   'application/json',
                 'Authorization',  'Bearer ' || v_service_key
               )
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never block the INSERT; log and continue
  RAISE WARNING 'trigger_member_deal_request_confirmation_email failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- Drop & recreate trigger (idempotent)
DROP TRIGGER IF EXISTS on_deal_authorization_send_member_confirmation
  ON public.deal_authorizations;

CREATE TRIGGER on_deal_authorization_send_member_confirmation
  AFTER INSERT ON public.deal_authorizations
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_member_deal_request_confirmation_email();

-- ============================================================
-- TRIGGER 2 – Payment success → member
-- Fires on every INSERT into deal_receipts.
-- The receipts table already stores member_email, member_name,
-- business_name, discount_name, receipt_number, and amount, so
-- no extra joins are needed.
-- ============================================================

CREATE OR REPLACE FUNCTION public.trigger_member_payment_success_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_supabase_url  TEXT;
  v_service_key   TEXT;
  v_edge_url      TEXT;
  v_member_email  TEXT;
  v_member_name   TEXT;
BEGIN
  v_supabase_url := coalesce(
    current_setting('app.settings.supabase_url', true),
    'https://qdrotavcmmevhgveodcp.supabase.co'
  );
  v_service_key := current_setting('app.settings.service_role_key', true);

  IF v_service_key IS NULL OR v_service_key = '' THEN
    RAISE WARNING 'trigger_member_payment_success_email: service_role_key not set – skipping';
    RETURN NEW;
  END IF;

  v_edge_url := v_supabase_url || '/functions/v1/send-member-payment-success-email';

  -- Prefer the denormalised columns already in deal_receipts; fall back to profiles
  v_member_email := NEW.member_email;
  v_member_name  := NEW.member_name;

  IF v_member_email IS NULL THEN
    SELECT p.email,
           trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, ''))
    INTO   v_member_email, v_member_name
    FROM   public.profiles p
    WHERE  p.id = NEW.member_id;
  END IF;

  IF v_member_email IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM extensions.net.http_post(
    url     := v_edge_url,
    body    := jsonb_build_object(
                 'member_id',             NEW.member_id,
                 'member_email',          v_member_email,
                 'member_name',           v_member_name,
                 'business_name',         NEW.business_name,
                 'deal_name',             NEW.discount_name,
                 'amount',                NEW.amount,
                 'receipt_number',        NEW.receipt_number,
                 'payment_method',        NEW.payment_method,
                 'deal_authorization_id', NEW.deal_authorization_id
               ),
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || v_service_key
               )
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trigger_member_payment_success_email failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- Drop & recreate trigger (idempotent)
DROP TRIGGER IF EXISTS on_deal_receipt_send_member_payment_email
  ON public.deal_receipts;

CREATE TRIGGER on_deal_receipt_send_member_payment_email
  AFTER INSERT ON public.deal_receipts
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_member_payment_success_email();

-- ============================================================
-- Verification
-- ============================================================
-- Check triggers are registered:
SELECT tgname, tgrelid::regclass AS table_name, tgenabled
FROM   pg_trigger
WHERE  tgname IN (
  'on_deal_authorization_send_member_confirmation',
  'on_deal_receipt_send_member_payment_email'
);
