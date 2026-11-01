-- Restaurant deal types (deal_type 'restaurant_*'):
--   restaurant_food_percent  % off food (drinks etc. excluded)
--   restaurant_bogo          2-for-1 / buy X get Y free
--   restaurant_set_menu      set menu at a fixed price
--   restaurant_kids_free     kids eat free with paying adults
--   restaurant_happy_hour    % off selected items in time slots
--   restaurant_free_item     free item with qualifying item (e.g. dessert with a main)
--   restaurant_group         % off the bill for tables of N+
--   restaurant_birthday      birthday-week treat (needs profiles.date_of_birth)
--
-- Type settings live in trusted_partner_discounts.custom_data. Availability
-- lives in schedule_data with type 'weekly' (optional date range + weekdays +
-- time slots, South African time, claim grace for bills paid after a slot).
-- Member inputs are sent in deal_authorizations.bill_data->'restaurant'.
--
-- Additive only and safe to apply while older app versions are live:
--   * older apps never see restaurant deals (restrictive RLS policy keyed on
--     the x-ll-capabilities request header sent by app 1.0.11+)
--   * the request trigger only acts on restaurant deals
-- The discount is recalculated here so a member cannot change it.
-- Safe to run multiple times.

BEGIN;

-- ---------------------------------------------------------------------------
-- Client capability (sent by the app as the x-ll-capabilities header)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.client_supports_capability(p_capability TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT p_capability = ANY (
    string_to_array(
      replace(
        coalesce(
          nullif(current_setting('request.headers', true), '')::jsonb
            ->> 'x-ll-capabilities',
          ''
        ),
        ' ',
        ''
      ),
      ','
    )
  );
$$;

GRANT EXECUTE ON FUNCTION public.client_supports_capability(TEXT) TO anon, authenticated;

DROP POLICY IF EXISTS "Restaurant deals require a supporting app version"
  ON public.trusted_partner_discounts;

CREATE POLICY "Restaurant deals require a supporting app version"
  ON public.trusted_partner_discounts
  AS RESTRICTIVE
  FOR SELECT
  TO anon, authenticated
  USING (
    coalesce(deal_type, '') NOT LIKE 'restaurant\_%'
    OR public.client_supports_capability('restaurant_deals_v1')
  );

-- ---------------------------------------------------------------------------
-- Availability (South African time, no DST)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.restaurant_deal_is_available(
  p_schedule JSONB,
  p_at TIMESTAMPTZ DEFAULT now()
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_now TIMESTAMP := p_at AT TIME ZONE 'Africa/Johannesburg';
  v_grace INTERVAL;
  v_start_date DATE;
  v_end_date DATE;
  v_days JSONB;
  v_slots JSONB;
  v_day DATE;
  v_slot JSONB;
  v_slot_start TIMESTAMP;
  v_slot_end TIMESTAMP;
BEGIN
  IF p_schedule IS NULL OR coalesce(p_schedule ->> 'type', '') <> 'weekly' THEN
    RETURN TRUE;
  END IF;

  v_grace := make_interval(
    mins => greatest(0, least(coalesce(nullif(p_schedule ->> 'claim_grace_minutes', '')::INT, 0), 360))
  );
  v_start_date := nullif(p_schedule ->> 'start_date', '')::DATE;
  v_end_date := nullif(p_schedule ->> 'end_date', '')::DATE;
  v_days := p_schedule -> 'day_of_weeks';
  v_slots := p_schedule -> 'time_slots';
  IF jsonb_typeof(v_slots) IS DISTINCT FROM 'array' OR jsonb_array_length(v_slots) = 0 THEN
    v_slots := '[{"start":"00:00","end":"24:00"}]'::JSONB;
  END IF;

  -- A slot on day D is claimable from its start until its end + grace, so the
  -- previous day is checked too for slots whose grace runs past midnight.
  FOREACH v_day IN ARRAY ARRAY[v_now::DATE, (v_now - v_grace)::DATE] LOOP
    CONTINUE WHEN v_start_date IS NOT NULL AND v_day < v_start_date;
    CONTINUE WHEN v_end_date IS NOT NULL AND v_day > v_end_date;
    CONTINUE WHEN jsonb_typeof(v_days) = 'array'
      AND jsonb_array_length(v_days) > 0
      AND NOT v_days @> to_jsonb(extract(isodow FROM v_day)::INT - 1);

    FOR v_slot IN SELECT value FROM jsonb_array_elements(v_slots) LOOP
      v_slot_start := v_day + (v_slot ->> 'start')::INTERVAL;
      v_slot_end := v_day + (v_slot ->> 'end')::INTERVAL + v_grace;
      IF v_now >= v_slot_start AND v_now < v_slot_end THEN
        RETURN TRUE;
      END IF;
    END LOOP;
  END LOOP;

  RETURN FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.restaurant_deal_is_available(JSONB, TIMESTAMPTZ) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- Discount calculation (mirrors lib/models/restaurant_deal.dart)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._rd_num(p JSONB, p_key TEXT, p_default NUMERIC DEFAULT 0)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT coalesce(nullif(p ->> p_key, '')::NUMERIC, p_default);
$$;

CREATE OR REPLACE FUNCTION public._rd_qty(p JSONB, p_key TEXT)
RETURNS INT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v NUMERIC := public._rd_num(p, p_key, 0);
BEGIN
  IF v < 0 OR v > 200 OR v <> trunc(v) THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: Please check the numbers you entered.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN v::INT;
END;
$$;

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
  v_group INT;
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
      v_group := greatest(0, public._rd_num(c, 'buy_qty', 1)::INT)
               + greatest(0, public._rd_num(c, 'free_qty', 1)::INT);
      v_free := CASE WHEN v_group > 0
        THEN (public._rd_qty(i, 'item_qty') / v_group)
             * greatest(0, public._rd_num(c, 'free_qty', 1)::INT)
        ELSE 0 END;
      IF v_max > 0 THEN v_free := least(v_free, v_max); END IF;
      v_discount := v_free * greatest(0, public._rd_num(c, 'item_price', 0));

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
        -- 29 Feb birthdays fall back to 28 Feb in non-leap years.
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

REVOKE ALL ON FUNCTION public.restaurant_deal_discount(UUID, UUID, JSONB, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Request validation (deal_authorizations insert)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_restaurant_deal_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request_role TEXT := coalesce(auth.jwt() ->> 'role', '');
  v_type TEXT;
  v_schedule JSONB;
  v_active BOOLEAN;
  v_bill NUMERIC;
  v_tip NUMERIC;
  v_expected NUMERIC;
  v_total NUMERIC;
BEGIN
  IF NEW.discount_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT d.deal_type, d.schedule_data, d.is_active
    INTO v_type, v_schedule, v_active
  FROM public.trusted_partner_discounts d
  WHERE d.id = NEW.discount_id;

  IF NOT FOUND OR coalesce(v_type, '') NOT LIKE 'restaurant\_%' THEN
    RETURN NEW;
  END IF;

  NEW.deal_type := v_type;

  IF v_request_role NOT IN ('anon', 'authenticated') THEN
    RETURN NEW;
  END IF;

  IF NOT coalesce(v_active, FALSE) THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_INACTIVE: This deal is no longer active.'
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT public.restaurant_deal_is_available(v_schedule, now()) THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_UNAVAILABLE: This deal is not available right now.'
      USING ERRCODE = 'P0001';
  END IF;

  IF NEW.bill_data IS NULL OR jsonb_typeof(NEW.bill_data) <> 'object' THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: Please enter your bill details.'
      USING ERRCODE = 'P0001';
  END IF;

  v_bill := public._rd_num(NEW.bill_data, 'original_bill_amount', 0);
  v_tip := public._rd_num(NEW.bill_data, 'tip_amount', 0);
  IF v_tip < 0 OR v_tip > greatest(v_bill, 0) THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: Please check the tip amount.'
      USING ERRCODE = 'P0001';
  END IF;

  v_expected := public.restaurant_deal_discount(
    NEW.discount_id,
    coalesce(auth.uid(), NEW.member_id),
    NEW.bill_data,
    now()
  );
  v_total := round(v_bill - v_expected + v_tip, 2);

  IF abs(coalesce(NEW.applied_discount_amount, -1) - v_expected) > 0.02
     OR abs(coalesce(NEW.amount, -1) - v_total) > 0.02 THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_MISMATCH: The deal amount has changed. Please reopen the deal and try again.'
      USING ERRCODE = 'P0001';
  END IF;

  IF NEW.payment_method = 'in_app' AND v_total <= 0 THEN
    RAISE EXCEPTION 'RESTAURANT_DEAL_INVALID: Nothing to pay in the app. Please choose Pay in store.'
      USING ERRCODE = 'P0001';
  END IF;

  NEW.applied_discount_amount := v_expected;
  NEW.amount := v_total;
  NEW.bill_data := NEW.bill_data || jsonb_build_object(
    'discount_amount', v_expected,
    'final_amount', v_total
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_restaurant_deal_request
  ON public.deal_authorizations;

CREATE TRIGGER trg_validate_restaurant_deal_request
  BEFORE INSERT ON public.deal_authorizations
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_restaurant_deal_request();

-- ---------------------------------------------------------------------------
-- Basic setup validation for restaurant deals
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_restaurant_deal_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_pct NUMERIC;
BEGIN
  IF coalesce(NEW.deal_type, '') NOT LIKE 'restaurant\_%' THEN
    RETURN NEW;
  END IF;

  IF NEW.deal_type NOT IN (
    'restaurant_food_percent', 'restaurant_bogo', 'restaurant_set_menu',
    'restaurant_kids_free', 'restaurant_happy_hour', 'restaurant_free_item',
    'restaurant_group', 'restaurant_birthday'
  ) THEN
    RAISE EXCEPTION 'Unknown restaurant deal type %', NEW.deal_type
      USING ERRCODE = '23514';
  END IF;

  IF NEW.custom_data IS NULL OR jsonb_typeof(NEW.custom_data) <> 'object' THEN
    RAISE EXCEPTION 'Restaurant deals need their deal settings'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.schedule_data IS NULL OR coalesce(NEW.schedule_data ->> 'type', '') <> 'weekly' THEN
    RAISE EXCEPTION 'Restaurant deals need a weekly schedule'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.deal_type IN ('restaurant_food_percent', 'restaurant_happy_hour', 'restaurant_group')
     OR (NEW.deal_type = 'restaurant_birthday' AND NEW.custom_data ->> 'reward' = 'percent') THEN
    v_pct := public._rd_num(NEW.custom_data, 'percentage', 0);
    IF v_pct <= 0 OR v_pct > 100 THEN
      RAISE EXCEPTION 'Restaurant deal percentage must be between 1 and 100'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF NEW.deal_type = 'restaurant_happy_hour'
     AND (jsonb_typeof(NEW.schedule_data -> 'time_slots') IS DISTINCT FROM 'array'
          OR jsonb_array_length(NEW.schedule_data -> 'time_slots') = 0) THEN
    RAISE EXCEPTION 'Happy hour deals need at least one time slot'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_restaurant_deal_rules
  ON public.trusted_partner_discounts;

CREATE TRIGGER trg_enforce_restaurant_deal_rules
  BEFORE INSERT OR UPDATE ON public.trusted_partner_discounts
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_restaurant_deal_rules();

COMMIT;
