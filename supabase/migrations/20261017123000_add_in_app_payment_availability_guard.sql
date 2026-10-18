-- In-app payment availability guard.
-- Members must not be able to request an in-app (Paystack) payment for a deal
-- when the trusted partner has no Paystack subaccount (banking details not
-- loaded). Members cannot read trusted_partner_bank_accounts under RLS, so the
-- check is exposed through SECURITY DEFINER RPCs that only return booleans.
--
-- The availability rule deliberately mirrors (and is a superset of) the
-- subaccount lookup in DealApprovalPopupService._fetchPayoutContext, so any
-- partner that can be paid in-app today is never blocked by this guard.
-- Additive only (new functions, no trigger): safe to apply while the current
-- Play Store version is live. The enforcing trigger is in 20261017123100.
-- Safe to run multiple times.

BEGIN;

CREATE OR REPLACE FUNCTION public._tp_has_in_app_payout_account(
  p_trusted_partner_id UUID,
  p_owner_member_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    (p_trusted_partner_id IS NULL AND p_owner_member_id IS NULL)
    OR EXISTS (
      SELECT 1
      FROM public.trusted_partner_bank_accounts ba
      WHERE ba.user_id IN (p_trusted_partner_id, p_owner_member_id)
        AND nullif(btrim(ba.subaccount_code), '') IS NOT NULL
    )
    OR EXISTS (
      SELECT 1
      FROM public.trusted_partners tp
      WHERE tp.user_id IN (p_trusted_partner_id, p_owner_member_id)
        AND coalesce(
          nullif(btrim(tp.paystack_subaccount_code), ''),
          nullif(btrim(tp.paystack_subaccount_id), '')
        ) IS NOT NULL
    );
$$;

REVOKE ALL ON FUNCTION public._tp_has_in_app_payout_account(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._tp_has_in_app_payout_account(UUID, UUID) FROM anon, authenticated;

-- Returns TRUE when members may choose "Pay through App" for this deal.
-- Unknown deals return TRUE so this guard never blocks on missing data; the
-- existing payment-time subaccount check still applies.
CREATE OR REPLACE FUNCTION public.discount_accepts_in_app_payment(p_discount_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trusted_partner_id UUID;
  v_owner_member_id UUID;
BEGIN
  SELECT d.trusted_partner_id, b.owner_member_id
    INTO v_trusted_partner_id, v_owner_member_id
  FROM public.trusted_partner_discounts d
  LEFT JOIN public.businesses b ON b.id = d.business_id
  WHERE d.id = p_discount_id;

  IF NOT FOUND THEN
    RETURN TRUE;
  END IF;

  RETURN public._tp_has_in_app_payout_account(v_trusted_partner_id, v_owner_member_id);
END;
$$;

REVOKE ALL ON FUNCTION public.discount_accepts_in_app_payment(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.discount_accepts_in_app_payment(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.discount_accepts_in_app_payment(UUID) TO authenticated;

-- Tells the partner that members tried to pay in-app but their banking
-- details are missing. At most one notification per partner per 24 hours.
CREATE OR REPLACE FUNCTION public.notify_tp_in_app_payment_unavailable(p_discount_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trusted_partner_id UUID;
  v_owner_member_id UUID;
  v_recipient UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;

  SELECT d.trusted_partner_id, b.owner_member_id
    INTO v_trusted_partner_id, v_owner_member_id
  FROM public.trusted_partner_discounts d
  LEFT JOIN public.businesses b ON b.id = d.business_id
  WHERE d.id = p_discount_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_recipient := coalesce(v_owner_member_id, v_trusted_partner_id);
  IF v_recipient IS NULL
     OR public._tp_has_in_app_payout_account(v_trusted_partner_id, v_owner_member_id) THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.notifications n
    WHERE n.user_id = v_recipient
      AND n.type = 'in_app_payment_unavailable'
      AND n.created_at > now() - interval '24 hours'
  ) THEN
    RETURN;
  END IF;

  INSERT INTO public.notifications (user_id, title, message, type, data, is_read)
  VALUES (
    v_recipient,
    'Members want to pay through the app',
    'A member tried to pay for your deal through the Local Lekker app, but your banking details are not loaded yet, so they were asked to pay in store. Add your banking details in your Business Profile to start receiving in-app payments.',
    'in_app_payment_unavailable',
    jsonb_build_object('discount_id', p_discount_id),
    FALSE
  );
END;
$$;

REVOKE ALL ON FUNCTION public.notify_tp_in_app_payment_unavailable(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_tp_in_app_payment_unavailable(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.notify_tp_in_app_payment_unavailable(UUID) TO authenticated;

COMMIT;
