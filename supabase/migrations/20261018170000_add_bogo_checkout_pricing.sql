-- BOGO pricing_mode defaults to fixed for existing deals.
-- Checkout prices are partner-entered and redeemed through a verified QR session.
BEGIN;

CREATE OR REPLACE FUNCTION public._rd_bogo_discount(
  p_config JSONB,
  p_inputs JSONB,
  p_bill NUMERIC
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_group INT := greatest(0, public._rd_num(p_config, 'buy_qty', 1)::INT)
    + greatest(0, public._rd_num(p_config, 'free_qty', 1)::INT);
  v_qty INT := public._rd_qty(p_inputs, 'item_qty');
  v_free INT;
  v_max INT := greatest(0, public._rd_num(p_config, 'max_free', 0)::INT);
  v_prices JSONB := p_inputs -> 'item_prices';
  v_total NUMERIC;
  v_discount NUMERIC;
BEGIN
  v_free := CASE WHEN v_group > 0
    THEN (v_qty / v_group) * greatest(0, public._rd_num(p_config, 'free_qty', 1)::INT)
    ELSE 0 END;
  IF v_max > 0 THEN v_free := least(v_free, v_max); END IF;

  IF coalesce(p_config ->> 'pricing_mode', 'fixed') = 'fixed' THEN
    RETURN v_free * greatest(0, public._rd_num(p_config, 'item_price', 0));
  ELSIF p_config ->> 'pricing_mode' IS DISTINCT FROM 'checkout' THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: Choose fixed price or price entered at checkout.'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_qty < 1 OR jsonb_typeof(v_prices) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: Enter one price for every qualifying item (maximum 200).'
      USING ERRCODE = 'P0001';
  END IF;
  IF jsonb_array_length(v_prices) <> v_qty THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: Enter one price for every qualifying item (maximum 200).'
      USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_prices) AS p(value)
             WHERE jsonb_typeof(value) IS DISTINCT FROM 'number') THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: Enter valid item prices with at most two decimal places.'
      USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(v_prices) AS p(value)
             WHERE value::NUMERIC <= 0 OR value::NUMERIC > 100000
                OR value::NUMERIC <> round(value::NUMERIC, 2)) THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: Enter valid item prices with at most two decimal places.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT sum(value::NUMERIC) INTO v_total
  FROM jsonb_array_elements_text(v_prices) AS p(value);
  IF v_total > p_bill THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: Qualifying item prices cannot exceed the original bill.'
      USING ERRCODE = 'P0001';
  END IF;
  SELECT coalesce(sum(price), 0) INTO v_discount
  FROM (
    SELECT value::NUMERIC AS price
    FROM jsonb_array_elements_text(v_prices) AS p(value)
    ORDER BY price
    LIMIT v_free
  ) AS free_items;
  RETURN v_discount;
END;
$$;

REVOKE ALL ON FUNCTION public._rd_bogo_discount(JSONB, JSONB, NUMERIC)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.restaurant_deal_discount(
  p_discount_id UUID,
  p_member_id UUID,
  p_bill_data JSONB,
  p_at TIMESTAMPTZ DEFAULT now()
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT;
  c JSONB;
  i JSONB := coalesce(p_bill_data -> 'restaurant' -> 'inputs', '{}'::JSONB);
  v_bill NUMERIC := public._rd_num(p_bill_data, 'original_bill_amount', 0);
  v_pct NUMERIC;
  v_amount NUMERIC;
  v_free INT;
  v_max INT;
  v_dob DATE;
  v_today DATE := (p_at AT TIME ZONE 'Africa/Johannesburg')::DATE;
  v_window INT;
  v_year INT;
  v_bday DATE;
  v_in_window BOOLEAN := FALSE;
  v_discount NUMERIC := 0;
BEGIN
  SELECT d.deal_type, coalesce(d.custom_data, '{}'::JSONB)
    INTO v_type, c
  FROM public.trusted_partner_discounts d
  WHERE d.id = p_discount_id;

  IF NOT FOUND OR coalesce(v_type, '') NOT LIKE 'restaurant\_%' THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: This deal could not be found.'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_bill <= 0 OR v_bill > 100000 THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: Please enter your bill total.'
      USING ERRCODE = 'P0001';
  END IF;

  v_pct := greatest(0, least(public._rd_num(c, 'percentage', 0), 100));
  v_max := greatest(0, public._rd_num(c, 'max_free', 0)::INT);

  CASE v_type
    WHEN 'restaurant_food_percent' THEN
      v_amount := public._rd_num(i, 'excluded_amount', 0);
      IF v_amount < 0 OR v_amount > v_bill THEN
        RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: Excluded items cannot be more than the bill.'
          USING ERRCODE = 'P0001';
      END IF;
      v_discount := (v_bill - v_amount) * v_pct / 100;

    WHEN 'restaurant_happy_hour' THEN
      v_amount := public._rd_num(i, 'qualifying_amount', 0);
      IF v_amount < 0 OR v_amount > v_bill THEN
        RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: Happy hour items cannot be more than the bill.'
          USING ERRCODE = 'P0001';
      END IF;
      v_discount := v_amount * v_pct / 100;

    WHEN 'restaurant_bogo' THEN
      IF c ->> 'pricing_mode' = 'checkout' AND NOT EXISTS (
        SELECT 1 FROM public.trusted_partner_discounts d
        JOIN public.businesses b ON b.id = d.business_id
        WHERE d.id = p_discount_id AND b.owner_member_id = auth.uid()
      ) THEN
        RAISE EXCEPTION 'RESTAURANT_DEAL_PARTNER_CHECKOUT_REQUIRED: Show your member QR to the partner to redeem this deal in store.'
          USING ERRCODE = 'P0001';
      END IF;
      v_discount := public._rd_bogo_discount(c, i, v_bill);

    WHEN 'restaurant_set_menu' THEN
      v_discount := public._rd_qty(i, 'menu_qty')
        * greatest(0, public._rd_num(c, 'normal_price', 0) - public._rd_num(c, 'set_price', 0));

    WHEN 'restaurant_kids_free' THEN
      v_free := least(
        public._rd_qty(i, 'kid_qty'),
        public._rd_qty(i, 'adult_qty') * greatest(1, public._rd_num(c, 'kids_per_adult', 1)::INT)
      );
      IF v_max > 0 THEN v_free := least(v_free, v_max); END IF;
      v_discount := v_free * greatest(0, public._rd_num(c, 'kid_meal_value', 0));

    WHEN 'restaurant_free_item' THEN
      v_free := least(
        public._rd_qty(i, 'free_qty'),
        public._rd_qty(i, 'qualifying_qty') * greatest(1, public._rd_num(c, 'free_per_qualifying', 1)::INT)
      );
      IF v_max > 0 THEN v_free := least(v_free, v_max); END IF;
      v_discount := v_free * greatest(0, public._rd_num(c, 'free_item_value', 0));

    WHEN 'restaurant_group' THEN
      IF public._rd_qty(i, 'party_size') < greatest(1, public._rd_num(c, 'min_party_size', 1)::INT) THEN
        RAISE EXCEPTION 'RESTAURANT_DEAL_GROUP_TOO_SMALL: This deal needs a table of at least % people.',
          greatest(1, public._rd_num(c, 'min_party_size', 1)::INT)
          USING ERRCODE = 'P0001';
      END IF;
      v_discount := v_bill * v_pct / 100;

    WHEN 'restaurant_birthday' THEN
      SELECT (p.date_of_birth AT TIME ZONE 'Africa/Johannesburg')::DATE
        INTO v_dob
      FROM public.profiles p
      WHERE p.id = p_member_id;

      IF v_dob IS NULL THEN
        RAISE EXCEPTION 'RESTAURANT_DEAL_BIRTHDAY_MISSING_DOB: Add your date of birth to your profile to use birthday deals.'
          USING ERRCODE = 'P0001';
      END IF;

      v_window := greatest(0, least(public._rd_num(c, 'window_days', 3)::INT, 31));
      FOREACH v_year IN ARRAY ARRAY[
        extract(year FROM v_today)::INT - 1,
        extract(year FROM v_today)::INT,
        extract(year FROM v_today)::INT + 1
      ] LOOP
        v_bday := make_date(
          v_year,
          extract(month FROM v_dob)::INT,
          least(
            extract(day FROM v_dob)::INT,
            extract(day FROM (make_date(v_year, extract(month FROM v_dob)::INT, 1) + INTERVAL '1 month - 1 day'))::INT
          )
        );
        IF abs(v_today - v_bday) <= v_window THEN
          v_in_window := TRUE;
        END IF;
      END LOOP;

      IF NOT v_in_window THEN
        RAISE EXCEPTION 'RESTAURANT_DEAL_BIRTHDAY_NOT_IN_WINDOW: This birthday deal is only available within % days of your birthday.',
          v_window
          USING ERRCODE = 'P0001';
      END IF;
      IF EXISTS (
        SELECT 1
        FROM public.deal_authorizations a
        WHERE a.member_id = p_member_id
          AND a.discount_id = p_discount_id
          AND a.status IN ('pending', 'approved', 'completed')
          AND a.created_at > p_at - INTERVAL '300 days'
      ) THEN
        RAISE EXCEPTION 'RESTAURANT_DEAL_BIRTHDAY_USED: You have already used this birthday deal this year.'
          USING ERRCODE = 'P0001';
      END IF;

      IF coalesce(c ->> 'reward', 'free_item') = 'percent' THEN
        v_discount := v_bill * v_pct / 100;
      ELSE
        v_discount := greatest(0, public._rd_num(c, 'free_item_value', 0));
      END IF;

    ELSE
      RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: Unknown restaurant deal type.'
        USING ERRCODE = 'P0001';
  END CASE;

  RETURN round(least(greatest(v_discount, 0), v_bill), 2);
END;
$$;

REVOKE ALL ON FUNCTION public.restaurant_deal_discount(UUID, UUID, JSONB, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.enforce_bogo_pricing_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  c JSONB := '{"buy_qty":1,"free_qty":1,"max_free":0}'::JSONB
    || coalesce(NEW.custom_data, '{}'::JSONB);
  v_mode TEXT := coalesce(c ->> 'pricing_mode', 'fixed');
  v_price NUMERIC;
BEGIN
  IF NEW.deal_type IS DISTINCT FROM 'restaurant_bogo' THEN RETURN NEW; END IF;
  IF v_mode NOT IN ('fixed', 'checkout') THEN
    RAISE EXCEPTION 'Choose fixed price or price entered at checkout.'
      USING ERRCODE = '23514';
  END IF;
  IF nullif(trim(c ->> 'item_name'), '') IS NULL THEN
    RAISE EXCEPTION 'Enter the item name.' USING ERRCODE = '23514';
  END IF;
  IF public._rd_qty(c, 'buy_qty') < 1
     OR public._rd_qty(c, 'free_qty') < 1
     OR public._rd_qty(c, 'max_free') < 0 THEN
    RAISE EXCEPTION 'Buy and free quantities must be between 1 and 200.'
      USING ERRCODE = '23514';
  END IF;
  IF v_mode = 'fixed' THEN
    v_price := public._rd_num(c, 'item_price', 0);
    IF v_price <= 0 OR v_price > 100000 OR v_price <> round(v_price, 2)
       OR v_price::TEXT IN ('NaN', 'Infinity', '-Infinity') THEN
      RAISE EXCEPTION 'Enter a valid fixed item price with at most two decimal places.'
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_bogo_pricing_rules ON public.trusted_partner_discounts;
CREATE TRIGGER trg_enforce_bogo_pricing_rules
  BEFORE INSERT OR UPDATE OF deal_type, custom_data ON public.trusted_partner_discounts
  FOR EACH ROW EXECUTE FUNCTION public.enforce_bogo_pricing_rules();

-- Direct authorization inserts must also use the existing verified session path.
CREATE OR REPLACE FUNCTION public.require_bogo_partner_checkout()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.trusted_partner_discounts d
    WHERE d.id = NEW.discount_id AND d.deal_type = 'restaurant_bogo'
      AND d.custom_data ->> 'pricing_mode' = 'checkout'
  ) AND (
    NEW.bill_data ->> 'source' IS DISTINCT FROM 'partner_qr'
    OR NEW.bill_data ->> 'redemption_session_id' IS NULL
    OR NEW.payment_method IS DISTINCT FROM 'pos'
    OR NEW.status IS DISTINCT FROM 'completed'
  ) THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_PARTNER_CHECKOUT_REQUIRED: Show your member QR to the partner to redeem this deal in store.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_require_bogo_partner_checkout ON public.deal_authorizations;
CREATE TRIGGER trg_require_bogo_partner_checkout
  BEFORE INSERT ON public.deal_authorizations
  FOR EACH ROW EXECUTE FUNCTION public.require_bogo_partner_checkout();

COMMIT;
