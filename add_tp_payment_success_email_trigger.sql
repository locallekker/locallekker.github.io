-- ============================================================
-- Trusted Partner Payment-Success Email Trigger
-- ============================================================
-- Ensures the TRUSTED PARTNER receives a "Payment Received" email
-- whenever a member completes a deal payment — regardless of which
-- app code path generated the receipt (new-card webview, saved-card
-- charge, pending-payments page, or any future path).
--
-- WHY THIS EXISTS
-- ---------------
-- Previously the TP email (send-payment-success-email) was only fired
-- from the new-card webview path in app code. The saved-card payment
-- path (deal_approval_popup_service) inserts a deal_receipts row but
-- never invoked the email, so TPs whose members paid with a saved card
-- never received a notification email.
--
-- The MEMBER payment email already works this way (see
-- add_member_email_triggers.sql -> on_deal_receipt_send_member_payment_email).
-- This script adds the matching TP-side trigger so both parties are
-- always emailed from a single, reliable database trigger.
--
-- NOTE: After deploying this trigger, the redundant in-app invocation
-- of send-payment-success-email in deal_payment_webview_page.dart is
-- removed to prevent the TP from receiving a duplicate email.
--
-- Prerequisites (same as add_member_email_triggers.sql)
-- -----------------------------------------------------
-- 1. pg_net extension enabled:
--      Dashboard -> Database -> Extensions -> pg_net  (enable)
--
-- 2. Service-role key stored as a database setting:
--      ALTER DATABASE postgres
--        SET "app.settings.service_role_key" = '<YOUR_SERVICE_ROLE_KEY>';
--
-- 3. The edge function is already deployed:
--      supabase functions deploy send-payment-success-email
-- ============================================================

-- Enable pg_net (idempotent)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ============================================================
-- Payment success -> trusted partner
-- Fires on every INSERT into deal_receipts.
-- The receipts table already stores trusted_partner_id, member_name,
-- business_name, discount_name, receipt_number, and amount, so no
-- extra joins are needed.
-- ============================================================

CREATE OR REPLACE FUNCTION public.trigger_tp_payment_success_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_supabase_url  TEXT;
  v_service_key   TEXT;
  v_edge_url      TEXT;
  v_deal_name     TEXT;
BEGIN
  v_supabase_url := coalesce(
    current_setting('app.settings.supabase_url', true),
    'https://qdrotavcmmevhgveodcp.supabase.co'
  );
  v_service_key := current_setting('app.settings.service_role_key', true);

  -- Skip silently if the key is not configured yet
  IF v_service_key IS NULL OR v_service_key = '' THEN
    RAISE WARNING 'trigger_tp_payment_success_email: service_role_key not set - skipping';
    RETURN NEW;
  END IF;

  -- Cannot email a TP we cannot identify
  IF NEW.trusted_partner_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_edge_url := v_supabase_url || '/functions/v1/send-payment-success-email';

  -- The edge function requires a non-null deal_name; fall back gracefully
  v_deal_name := coalesce(NEW.discount_name, 'your deal');

  -- Fire-and-forget HTTP call via pg_net. The edge function resolves the
  -- TP's email address from profiles using trusted_partner_id.
  PERFORM extensions.net.http_post(
    url     := v_edge_url,
    body    := jsonb_build_object(
                 'trusted_partner_id',     NEW.trusted_partner_id,
                 'member_name',            NEW.member_name,
                 'deal_name',              v_deal_name,
                 'amount',                 NEW.amount,
                 'receipt_number',         NEW.receipt_number,
                 'business_name',          NEW.business_name,
                 'deal_authorization_id',  NEW.deal_authorization_id
               ),
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || v_service_key
               )
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never block the INSERT; log and continue
  RAISE WARNING 'trigger_tp_payment_success_email failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- Drop & recreate trigger (idempotent)
DROP TRIGGER IF EXISTS on_deal_receipt_send_tp_payment_email
  ON public.deal_receipts;

CREATE TRIGGER on_deal_receipt_send_tp_payment_email
  AFTER INSERT ON public.deal_receipts
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_tp_payment_success_email();

-- ============================================================
-- Verification
-- ============================================================
-- Check both deal_receipts email triggers are registered:
SELECT tgname, tgrelid::regclass AS table_name, tgenabled
FROM   pg_trigger
WHERE  tgname IN (
  'on_deal_receipt_send_member_payment_email',
  'on_deal_receipt_send_tp_payment_email'
);
