BEGIN;

ALTER TABLE public.deal_authorizations
  ADD COLUMN IF NOT EXISTS qr_redemption_key UUID;

CREATE UNIQUE INDEX IF NOT EXISTS idx_deal_authorizations_qr_redemption_key
  ON public.deal_authorizations(qr_redemption_key)
  WHERE qr_redemption_key IS NOT NULL;

ALTER TABLE public.deal_authorizations
  ADD COLUMN IF NOT EXISTS bill_data JSONB;

ALTER TABLE public.deal_authorizations
  ADD COLUMN IF NOT EXISTS quantity INTEGER,
  ADD COLUMN IF NOT EXISTS member_entered_price NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS applied_discount_amount NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS deal_type TEXT,
  ADD COLUMN IF NOT EXISTS deal_snapshot JSONB;

CREATE OR REPLACE FUNCTION public.verify_member_qr_for_partner(
  p_business_id UUID,
  p_qr_payload TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
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

  SELECT p.name, p.surname, p.profile_photo_url, p.created_at,
         p.subscription, p.is_tp_member
    INTO v_profile
  FROM public.profiles p
  WHERE p.id = v_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'QR_REDEMPTION_MEMBER_NOT_FOUND: Member not found.'
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

  IF NOT coalesce(v_profile.is_tp_member, FALSE)
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

  RETURN jsonb_build_object(
    'member_id', v_member_id,
    'name', coalesce(v_profile.name, ''),
    'surname', coalesce(v_profile.surname, ''),
    'profile_photo_url', v_profile.profile_photo_url,
    'member_since', v_profile.created_at,
    'qr_expires_at', v_qr_expires_at,
    'membership_active', TRUE
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.redeem_deal_via_member_qr(
  p_business_id UUID,
  p_qr_payload TEXT,
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
DECLARE
  v_member JSONB;
  v_member_id UUID;
  v_owner_id UUID;
  v_deal public.trusted_partner_discounts%ROWTYPE;
  v_bill NUMERIC;
  v_tip NUMERIC;
  v_qty NUMERIC;
  v_unit_price NUMERIC;
  v_deal_price NUMERIC;
  v_discount NUMERIC;
  v_total NUMERIC;
  v_excluded NUMERIC;
  v_id UUID;
  v_existing RECORD;
  v_data JSONB;
BEGIN
  IF p_idempotency_key IS NULL THEN
    RAISE EXCEPTION 'QR_REDEMPTION_INVALID: Missing redemption key.'
      USING ERRCODE = 'P0001';
  END IF;

  v_member := public.verify_member_qr_for_partner(p_business_id, p_qr_payload);
  v_member_id := (v_member ->> 'member_id')::UUID;

  SELECT b.owner_member_id
    INTO v_owner_id
  FROM public.businesses b
  WHERE b.id = p_business_id;

  SELECT *
    INTO v_deal
  FROM public.trusted_partner_discounts d
  WHERE d.id = p_discount_id
    AND d.business_id = p_business_id
    AND d.is_active;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'QR_REDEMPTION_DEAL_UNAVAILABLE: This deal is no longer available.'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_deal.deal_type IN ('website_redirect', 'booking_redirect') THEN
    RAISE EXCEPTION 'QR_REDEMPTION_DEAL_UNAVAILABLE: This deal cannot be redeemed at the till.'
      USING ERRCODE = 'P0001';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(v_member_id::TEXT || ':' || p_discount_id::TEXT, 0)
  );

  IF NOT public.restaurant_deal_is_available(v_deal.schedule_data, now()) THEN
    RAISE EXCEPTION 'QR_REDEMPTION_DEAL_UNAVAILABLE: This deal is not available at this time.'
      USING ERRCODE = 'P0001';
  END IF;

  IF jsonb_typeof(p_checkout) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'QR_REDEMPTION_INVALID: Enter the checkout details.'
      USING ERRCODE = 'P0001';
  END IF;

  v_bill := coalesce(nullif(p_checkout ->> 'original_bill_amount', '')::NUMERIC, 0);
  v_tip := coalesce(nullif(p_checkout ->> 'tip_amount', '')::NUMERIC, 0);
  IF v_bill <= 0 OR v_bill > 100000 OR v_tip < 0 OR v_tip > v_bill THEN
    RAISE EXCEPTION 'QR_REDEMPTION_INVALID: Check the bill and tip amounts.'
      USING ERRCODE = 'P0001';
  END IF;

  IF coalesce(v_deal.deal_type, '') LIKE 'restaurant\_%' THEN
    v_discount := public.restaurant_deal_discount(
      p_discount_id,
      v_member_id,
      p_checkout,
      now()
    );
  ELSIF v_deal.is_bill_discount THEN
    v_excluded := coalesce(
      nullif(p_checkout -> 'checkout' ->> 'excluded_amount', '')::NUMERIC,
      0
    );
    IF v_excluded < 0 OR v_excluded > v_bill THEN
      RAISE EXCEPTION 'QR_REDEMPTION_INVALID: Excluded items cannot exceed the bill.'
        USING ERRCODE = 'P0001';
    END IF;
    IF coalesce((v_deal.bill_discount_data ->> 'isPercentage')::BOOLEAN, FALSE) THEN
      v_discount := (v_bill - v_excluded)
        * greatest(0, least(v_deal.percentage, 100)) / 100;
    ELSE
      v_discount := least(greatest(coalesce(v_deal.fixed_amount, 0), 0), v_bill - v_excluded);
    END IF;
  ELSE
    v_qty := coalesce(nullif(p_checkout -> 'checkout' ->> 'quantity', '')::NUMERIC, 0);
    IF v_qty <= 0 OR v_qty > (
      CASE WHEN v_deal.is_weight_based THEN 200000 ELSE 200 END
    ) THEN
      RAISE EXCEPTION 'QR_REDEMPTION_INVALID: Check the quantity or weight.'
        USING ERRCODE = 'P0001';
    END IF;

    IF v_deal.requires_manual_price AND v_deal.deal_type = 'percent_item' THEN
      v_unit_price := coalesce(
        nullif(p_checkout -> 'checkout' ->> 'unit_price', '')::NUMERIC,
        0
      );
      IF v_unit_price <= 0 OR v_unit_price > 100000 THEN
        RAISE EXCEPTION 'QR_REDEMPTION_INVALID: Enter a valid item price.'
          USING ERRCODE = 'P0001';
      END IF;
    ELSE
      v_unit_price := v_deal.item_price;
    END IF;

    IF v_deal.is_weight_based THEN
      v_qty := v_qty / 1000;
    END IF;

    IF v_deal.deal_type IN ('buy_get', 'buyget') THEN
      v_deal_price := coalesce(
        nullif(v_deal.custom_data ->> 'total_price', '')::NUMERIC,
        nullif(v_deal.custom_data ->> 'buy_item_price', '')::NUMERIC,
        v_unit_price
      );
      v_discount := greatest(
        0,
        coalesce(nullif(v_deal.custom_data ->> 'buy_item_price', '')::NUMERIC, v_unit_price)
          - v_deal_price
      ) * v_qty;
    ELSE
      IF v_deal.requires_manual_price AND v_deal.deal_type = 'percent_item' THEN
        v_discount := v_unit_price * greatest(0, least(v_deal.percentage, 100)) / 100;
      ELSIF coalesce(v_deal.fixed_amount, 0) > 0 THEN
        v_discount := least(v_deal.fixed_amount, v_unit_price);
      ELSE
        v_discount := v_unit_price * greatest(0, least(v_deal.percentage, 100)) / 100;
      END IF;
      v_discount := v_discount * v_qty;
    END IF;
  END IF;

  v_discount := round(greatest(0, least(v_discount, v_bill)), 2);
  v_total := round(v_bill - v_discount + v_tip, 2);
  IF p_pos_total IS NULL OR abs(p_pos_total - v_total) > 0.01 THEN
    RAISE EXCEPTION 'QR_REDEMPTION_POS_MISMATCH: Till total must match the calculated total of R%.',
      to_char(v_total, 'FM999999990.00')
      USING ERRCODE = 'P0001';
  END IF;

  SELECT a.id, a.member_id, a.discount_id, a.business_id, a.amount, a.bill_data
    INTO v_existing
  FROM public.deal_authorizations a
  WHERE a.qr_redemption_key = p_idempotency_key;

  IF FOUND THEN
    IF v_existing.member_id <> v_member_id
       OR v_existing.discount_id <> p_discount_id
       OR v_existing.business_id <> p_business_id
       OR v_existing.amount <> v_total
       OR (v_existing.bill_data - 'source' - 'discount_amount' - 'final_amount' - 'pos_total')
          <> p_checkout THEN
      RAISE EXCEPTION 'QR_REDEMPTION_KEY_REUSED: This checkout was already submitted.'
        USING ERRCODE = 'P0001';
    END IF;
    RETURN v_existing.id;
  END IF;

  IF v_deal.is_once_off AND EXISTS (
    SELECT 1
    FROM public.deal_authorizations a
    WHERE a.member_id = v_member_id
      AND a.discount_id = p_discount_id
      AND a.status IN ('pending', 'approved', 'completed')
  ) THEN
    RAISE EXCEPTION 'QR_REDEMPTION_ALREADY_USED: This member has already used this one-time deal.'
      USING ERRCODE = 'P0001';
  END IF;

  v_data := p_checkout || jsonb_build_object(
    'source', 'partner_qr',
    'discount_amount', v_discount,
    'final_amount', v_total,
    'pos_total', p_pos_total
  );

  INSERT INTO public.deal_authorizations (
    member_id,
    trusted_partner_id,
    business_id,
    discount_id,
    status,
    authorization_type,
    payment_method,
    amount,
    quantity,
    member_entered_price,
    applied_discount_amount,
    deal_type,
    deal_snapshot,
    bill_data,
    notes,
    completed_at,
    qr_redemption_key
  )
  VALUES (
    v_member_id,
    v_owner_id,
    p_business_id,
    p_discount_id,
    'completed',
    'in_store',
    'pos',
    v_total,
    CASE
      WHEN coalesce(v_deal.deal_type, '') LIKE 'restaurant\_%' THEN NULL
      ELSE coalesce(nullif(p_checkout -> 'checkout' ->> 'quantity', '')::NUMERIC, 1)::INT
    END,
    CASE
      WHEN v_deal.requires_manual_price THEN
        nullif(p_checkout -> 'checkout' ->> 'unit_price', '')::NUMERIC
      ELSE NULL
    END,
    v_discount,
    v_deal.deal_type,
    to_jsonb(v_deal),
    v_data,
    'Partner QR redemption',
    now(),
    p_idempotency_key
  )
  ON CONFLICT (qr_redemption_key)
    WHERE qr_redemption_key IS NOT NULL
    DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT a.id, a.member_id, a.discount_id, a.business_id, a.amount, a.bill_data
      INTO v_existing
    FROM public.deal_authorizations a
    WHERE a.qr_redemption_key = p_idempotency_key;
    IF NOT FOUND
       OR v_existing.member_id <> v_member_id
       OR v_existing.discount_id <> p_discount_id
       OR v_existing.business_id <> p_business_id
       OR v_existing.amount <> v_total
       OR (v_existing.bill_data - 'source' - 'discount_amount' - 'final_amount' - 'pos_total')
          <> p_checkout THEN
      RAISE EXCEPTION 'QR_REDEMPTION_KEY_REUSED: This checkout was already submitted.'
        USING ERRCODE = 'P0001';
    END IF;
    RETURN v_existing.id;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.verify_member_qr_for_partner(UUID, TEXT)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.redeem_deal_via_member_qr(UUID, TEXT, UUID, JSONB, NUMERIC, UUID)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_member_qr_for_partner(UUID, TEXT)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_deal_via_member_qr(UUID, TEXT, UUID, JSONB, NUMERIC, UUID)
  TO authenticated;

COMMIT;
