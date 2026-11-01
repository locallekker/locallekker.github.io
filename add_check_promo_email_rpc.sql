-- ============================================================
-- Pre-signup promo eligibility check
-- Returns minimal promo info if the given email is on the
-- participant list of an active intro campaign.
--
-- Runs as SECURITY DEFINER so it can be called by anon users
-- (during the signup form, before an auth.uid() exists) without
-- exposing the underlying promotion_participant_emails table.
-- ============================================================

CREATE OR REPLACE FUNCTION public.check_promo_eligibility_for_email(
  p_email TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := lower(trim(coalesce(p_email, '')));
  v_row   RECORD;
BEGIN
  IF v_email = '' THEN
    RETURN NULL;
  END IF;

  SELECT
    ppe.id   AS participant_id,
    p.id     AS promotion_id,
    p.name,
    p.description,
    p.free_months,
    p.initial_charge_cents,
    p.renewal_charge_cents,
    p.is_intro_campaign
  INTO v_row
  FROM public.promotion_participant_emails ppe
  JOIN public.promotions p ON p.id = ppe.promotion_id
  WHERE ppe.email = v_email
    AND ppe.is_claimed = false
    AND p.is_active = true
    AND p.is_intro_campaign = true
    AND (p.starts_at IS NULL OR p.starts_at <= now())
    AND (p.ends_at   IS NULL OR p.ends_at   >  now())
  ORDER BY ppe.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN json_build_object(
    'participant_id',        v_row.participant_id,
    'promotion_id',          v_row.promotion_id,
    'name',                  v_row.name,
    'description',           v_row.description,
    'free_months',           v_row.free_months,
    'initial_charge_cents',  v_row.initial_charge_cents,
    'renewal_charge_cents',  v_row.renewal_charge_cents
  );
END;
$$;

-- Allow both anonymous (pre-signup) and authenticated users to call it
GRANT EXECUTE ON FUNCTION public.check_promo_eligibility_for_email(TEXT) TO anon, authenticated;
