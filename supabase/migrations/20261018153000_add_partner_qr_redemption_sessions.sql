BEGIN;

CREATE TABLE IF NOT EXISTS public.partner_qr_redemption_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  partner_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  member_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '5 minutes'),
  redeemed_at TIMESTAMPTZ,
  redemption_id UUID REFERENCES public.deal_authorizations(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_partner_qr_redemption_sessions_expiry
  ON public.partner_qr_redemption_sessions(expires_at);

ALTER TABLE public.partner_qr_redemption_sessions ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.partner_qr_redemption_sessions
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.verify_member_qr_for_partner(
  p_business_id UUID,
  p_qr_payload TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_business_owner UUID;
  v_payload JSONB;
  v_member_id UUID;
  v_profile RECORD;
  v_qr_exp BIGINT;
  v_qr_expires_at TIMESTAMPTZ;
  v_session_id UUID;
  v_session RECORD;
  v_from_session BOOLEAN := FALSE;
  v_session_redeemed BOOLEAN := FALSE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'QR_REDEMPTION_UNAUTHORIZED: Sign in as a trusted partner to continue.'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_qr_payload IS NULL OR length(p_qr_payload) > 4096 THEN
    RAISE EXCEPTION 'QR_REDEMPTION_INVALID_QR: This member QR code is invalid.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT b.owner_member_id
    INTO v_business_owner
  FROM public.businesses b
  WHERE b.id = p_business_id;

  IF NOT FOUND OR v_business_owner <> auth.uid() THEN
    RAISE EXCEPTION 'QR_REDEMPTION_UNAUTHORIZED: You do not have access to this business.'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_qr_payload ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    v_session_id := p_qr_payload::UUID;
    SELECT s.member_id, s.expires_at, s.redeemed_at
      INTO v_session
    FROM public.partner_qr_redemption_sessions s
    WHERE s.id = v_session_id
      AND s.business_id = p_business_id
      AND s.partner_user_id = auth.uid()
      AND (s.expires_at > now() OR s.redeemed_at IS NOT NULL)
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'QR_REDEMPTION_SESSION_EXPIRED: Please scan the member QR code again.'
        USING ERRCODE = 'P0001';
    END IF;

    v_member_id := v_session.member_id;
    v_qr_expires_at := v_session.expires_at;
    v_from_session := TRUE;
    v_session_redeemed := v_session.redeemed_at IS NOT NULL;
  ELSE
    BEGIN
      v_payload := p_qr_payload::JSONB;
      v_member_id := nullif(v_payload ->> 'user_id', '')::UUID;
      v_qr_exp := nullif(v_payload ->> 'exp', '')::BIGINT;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'QR_REDEMPTION_INVALID_QR: This member QR code is invalid.'
        USING ERRCODE = 'P0001';
    END;

    IF coalesce(v_payload ->> 'type', '') NOT IN ('user_qr', 'user_qr_v2')
       OR v_member_id IS NULL
       OR (v_payload ->> 'type' = 'user_qr_v2'
           AND (v_qr_exp IS NULL
                OR v_qr_exp < 0
                OR v_qr_exp > extract(epoch FROM now() + interval '1 day')::BIGINT
                OR to_timestamp(v_qr_exp) <= now())) THEN
      RAISE EXCEPTION 'QR_REDEMPTION_INVALID_QR: This member QR code has expired or is invalid.'
        USING ERRCODE = 'P0001';
    END IF;

    SELECT q.expires_at
      INTO v_qr_expires_at
    FROM public.user_qr_codes q
    WHERE q.user_id = v_member_id
      AND q.qr_code = p_qr_payload
      AND q.is_active
      AND q.expires_at > now()
    ORDER BY q.created_at DESC
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'QR_REDEMPTION_INVALID_QR: This member QR code is no longer active.'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  SELECT p.name, p.surname, p.profile_photo_url, p.created_at,
         p.subscription, p.is_tp_member
    INTO v_profile
  FROM public.profiles p
  WHERE p.id = v_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'QR_REDEMPTION_MEMBER_NOT_FOUND: Member not found.'
      USING ERRCODE = 'P0001';
  END IF;

  IF (NOT v_from_session OR NOT v_session_redeemed)
     AND NOT coalesce(v_profile.is_tp_member, FALSE)
     AND coalesce(lower(v_profile.subscription), '') <> 'active'
     AND NOT EXISTS (
       SELECT 1
       FROM public.subscriptions s
       WHERE s.user_id = v_member_id
         AND s.status = 'active'
         AND (s.current_period_end IS NULL OR s.current_period_end > now())
     ) THEN
    RAISE EXCEPTION 'QR_REDEMPTION_INACTIVE_MEMBER: This member does not have an active membership.'
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT v_from_session THEN
    DELETE FROM public.partner_qr_redemption_sessions
    WHERE created_at < now() - interval '30 days';

    INSERT INTO public.partner_qr_redemption_sessions (
      business_id,
      partner_user_id,
      member_id,
      expires_at
    )
    VALUES (
      p_business_id,
      auth.uid(),
      v_member_id,
      now() + interval '5 minutes'
    )
    RETURNING id, expires_at INTO v_session_id, v_qr_expires_at;
  END IF;

  RETURN jsonb_build_object(
    'member_id', v_member_id,
    'name', coalesce(v_profile.name, ''),
    'surname', coalesce(v_profile.surname, ''),
    'profile_photo_url', v_profile.profile_photo_url,
    'member_since', v_profile.created_at,
    'redemption_expires_at', v_qr_expires_at,
    'redemption_session_id', v_session_id,
    'membership_active', TRUE
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.consume_partner_qr_redemption_session()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_id UUID;
  v_bill NUMERIC;
  v_extras NUMERIC;
BEGIN
  IF coalesce(NEW.bill_data ->> 'source', '') <> 'partner_qr' THEN
    RETURN NEW;
  END IF;

  BEGIN
    v_session_id := nullif(NEW.bill_data ->> 'redemption_session_id', '')::UUID;
  EXCEPTION WHEN OTHERS THEN
    v_session_id := NULL;
  END;

  IF v_session_id IS NULL OR auth.uid() IS NULL THEN
    RAISE EXCEPTION 'QR_REDEMPTION_SESSION_INVALID: Please scan the member QR code again.'
      USING ERRCODE = 'P0001';
  END IF;

  v_bill := coalesce(nullif(NEW.bill_data ->> 'original_bill_amount', '')::NUMERIC, 0);
  v_extras := coalesce(
    nullif(NEW.bill_data -> 'checkout' ->> 'extras_amount', '')::NUMERIC,
    0
  );
  IF v_extras < 0 OR v_extras > v_bill
     OR length(coalesce(NEW.bill_data -> 'checkout' ->> 'adjustments_note', '')) > 500 THEN
    RAISE EXCEPTION 'QR_REDEMPTION_INVALID: Check the extras or adjustment details.'
      USING ERRCODE = 'P0001';
  END IF;

  IF coalesce(NEW.applied_discount_amount, 0) <= 0 THEN
    RAISE EXCEPTION 'QR_REDEMPTION_INVALID: This bill does not qualify for savings from this deal.'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.partner_qr_redemption_sessions
  SET redeemed_at = now(),
      redemption_id = NEW.id
  WHERE id = v_session_id
    AND business_id = NEW.business_id
    AND partner_user_id = auth.uid()
    AND member_id = NEW.member_id
    AND redeemed_at IS NULL
    AND expires_at > now();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'QR_REDEMPTION_SESSION_EXPIRED: Please scan the member QR code again.'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_consume_partner_qr_redemption_session
  ON public.deal_authorizations;

CREATE TRIGGER trg_consume_partner_qr_redemption_session
  BEFORE INSERT ON public.deal_authorizations
  FOR EACH ROW
  EXECUTE FUNCTION public.consume_partner_qr_redemption_session();

CREATE OR REPLACE FUNCTION public.redeem_deal_via_redemption_session(
  p_business_id UUID,
  p_redemption_session_id UUID,
  p_discount_id UUID,
  p_checkout JSONB,
  p_pos_total NUMERIC,
  p_idempotency_key UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.redeem_deal_via_member_qr(
    p_business_id,
    p_redemption_session_id::TEXT,
    p_discount_id,
    p_checkout,
    p_pos_total,
    p_idempotency_key
  );
END;
$$;

REVOKE ALL ON FUNCTION public.verify_member_qr_for_partner(UUID, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_member_qr_for_partner(UUID, TEXT)
  TO authenticated;
REVOKE ALL ON FUNCTION public.redeem_deal_via_redemption_session(UUID, UUID, UUID, JSONB, NUMERIC, UUID)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.redeem_deal_via_redemption_session(UUID, UUID, UUID, JSONB, NUMERIC, UUID)
  TO authenticated;

COMMIT;
