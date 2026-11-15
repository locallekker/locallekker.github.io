BEGIN;

ALTER TABLE public.businesses
  ADD COLUMN IF NOT EXISTS sells_fresh_produce boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sells_alcohol boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS offers_sports_activities boolean NOT NULL DEFAULT false;

ALTER TABLE public.trusted_partner_discounts
  ADD COLUMN IF NOT EXISTS terms_revision uuid;

CREATE TABLE public.partner_deal_review_guard (
  transaction_id bigint NOT NULL,
  partner_id uuid NOT NULL,
  PRIMARY KEY (transaction_id, partner_id)
);
ALTER TABLE public.partner_deal_review_guard ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.partner_deal_review_guard FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.lock_partner_for_deal_creation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_business public.businesses;
  v_category text;
BEGIN
  SELECT * INTO STRICT v_business FROM public.businesses
    WHERE owner_member_id = NEW.trusted_partner_id FOR SHARE;
  v_category := CASE
    WHEN coalesce(v_business.sells_fresh_produce, false) THEN 'Fresh & Local'
    WHEN coalesce(v_business.sells_alcohol, false) THEN 'Local Sips'
    WHEN coalesce(v_business.offers_sports_activities, false) THEN 'Locally Active'
    WHEN v_business.category IN ('Restaurant', 'Food & Beverage', 'Local Eats') THEN 'Local Eats'
    WHEN v_business.category IN ('Fresh & Local', 'Local Sips', 'Locally Active') THEN v_business.category
    ELSE NULL END;
  IF (v_category IS NOT NULL AND NEW.deal_category IS DISTINCT FROM v_category)
     OR (v_category = 'Local Eats' AND coalesce(NEW.deal_type, '') NOT LIKE 'restaurant\_%' ESCAPE '\'
         AND NEW.deal_type IS DISTINCT FROM 'website_redirect')
     OR (NEW.deal_type = 'booking_redirect' AND v_category IS DISTINCT FROM 'Locally Active') THEN
    RAISE EXCEPTION 'DEAL_REVIEW_CHANGED: Partner category changed. Reload before creating a deal.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER lock_partner_for_deal_creation
BEFORE INSERT ON public.trusted_partner_discounts
FOR EACH ROW EXECUTE FUNCTION public.lock_partner_for_deal_creation();

CREATE OR REPLACE FUNCTION public.require_partner_deal_review()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (NEW.category, NEW.sells_fresh_produce, NEW.sells_alcohol, NEW.offers_sports_activities)
       IS DISTINCT FROM
     (OLD.category, OLD.sells_fresh_produce, OLD.sells_alcohol, OLD.offers_sports_activities)
     AND EXISTS (
       SELECT 1 FROM public.trusted_partner_discounts
       WHERE trusted_partner_id = OLD.owner_member_id
     )
     AND NOT EXISTS (
       SELECT 1 FROM public.partner_deal_review_guard
       WHERE transaction_id = txid_current() AND partner_id = OLD.owner_member_id
     ) THEN
    RAISE EXCEPTION 'PARTNER_DEAL_REVIEW_REQUIRED: Review every deal before changing the category';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER require_partner_deal_review
BEFORE UPDATE ON public.businesses
FOR EACH ROW EXECUTE FUNCTION public.require_partner_deal_review();

CREATE OR REPLACE FUNCTION public.require_current_deal_terms()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_revision uuid;
BEGIN
  IF NEW.discount_id IS NULL THEN RETURN NEW; END IF;
  SELECT terms_revision INTO v_revision
    FROM public.trusted_partner_discounts WHERE id = NEW.discount_id FOR SHARE;
  IF v_revision IS NOT NULL AND (
      NEW.deal_snapshot->>'terms_revision' IS DISTINCT FROM v_revision::text
      OR (NEW.bill_data->>'source' = 'partner_qr' AND
          NEW.bill_data->>'terms_revision' IS DISTINCT FROM v_revision::text)) THEN
    RAISE EXCEPTION 'DEAL_TERMS_CHANGED: This deal has changed. Reopen it and try again.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER aaa_require_current_deal_terms
BEFORE INSERT ON public.deal_authorizations
FOR EACH ROW EXECUTE FUNCTION public.require_current_deal_terms();

CREATE TRIGGER aaa_require_current_deal_terms_reopened
BEFORE UPDATE OF status, discount_id, deal_snapshot ON public.deal_authorizations
FOR EACH ROW
WHEN (OLD.status IN ('completed', 'rejected', 'cancelled', 'expired')
      AND (NEW.status IS NULL OR NEW.status NOT IN ('completed', 'rejected', 'cancelled', 'expired')))
EXECUTE FUNCTION public.require_current_deal_terms();

CREATE OR REPLACE FUNCTION public.require_deal_editor_revision()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF OLD.terms_revision IS NOT NULL AND NEW.terms_revision IS NULL THEN
    RAISE EXCEPTION 'DEAL_TERMS_CHANGED: This deal has changed. Reopen it and try again.';
  END IF;
  IF OLD.terms_revision IS NOT NULL
     AND (to_jsonb(NEW) - ARRAY['is_active', 'updated_at', 'terms_revision'])
       IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['is_active', 'updated_at', 'terms_revision'])
     AND NEW.terms_revision IS NOT DISTINCT FROM OLD.terms_revision THEN
    RAISE EXCEPTION 'DEAL_TERMS_CHANGED: This deal has changed. Reopen it and try again.';
  END IF;
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;
CREATE TRIGGER require_deal_editor_revision BEFORE UPDATE ON public.trusted_partner_discounts
FOR EACH ROW EXECUTE FUNCTION public.require_deal_editor_revision();

CREATE OR REPLACE FUNCTION public.admin_update_partner_with_reviewed_deals(
  payload jsonb,
  reviewed_deals jsonb,
  expected_partner jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_partner uuid := NULLIF(payload->>'partner_id', '')::uuid;
  v_business public.businesses;
  v_deal public.trusted_partner_discounts;
  v_entry jsonb;
  v_details jsonb;
  v_result jsonb;
  v_expected_category text;
  v_type text;
  v_count integer;
  v_data jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.memberships
    WHERE user_id = auth.uid() AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF v_partner IS NULL OR jsonb_typeof(reviewed_deals) IS DISTINCT FROM 'array'
     OR jsonb_typeof(expected_partner) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'A partner and a list of reviewed deals are required';
  END IF;
  SELECT * INTO STRICT v_business FROM public.businesses
    WHERE owner_member_id = v_partner FOR UPDATE;
  IF v_business.category IS DISTINCT FROM expected_partner->>'category'
     OR coalesce(v_business.sells_fresh_produce, false)
        IS DISTINCT FROM coalesce((expected_partner->>'sells_fresh_produce')::boolean, false)
     OR coalesce(v_business.sells_alcohol, false)
        IS DISTINCT FROM coalesce((expected_partner->>'sells_alcohol')::boolean, false)
     OR coalesce(v_business.offers_sports_activities, false)
        IS DISTINCT FROM coalesce((expected_partner->>'offers_sports_activities')::boolean, false) THEN
    RAISE EXCEPTION 'DEAL_REVIEW_CHANGED: Partner changed; reload and review again.';
  END IF;

  PERFORM 1 FROM public.trusted_partner_discounts
    WHERE trusted_partner_id = v_partner ORDER BY id FOR UPDATE;
  SELECT count(*) INTO v_count FROM public.trusted_partner_discounts
    WHERE trusted_partner_id = v_partner;
  IF jsonb_array_length(reviewed_deals) <> v_count OR
     (SELECT count(DISTINCT value->>'id') FROM jsonb_array_elements(reviewed_deals)) <> v_count THEN
    RAISE EXCEPTION 'DEAL_REVIEW_CHANGED: The deal list changed. Reload and review every deal again.';
  END IF;

  v_expected_category := CASE
    WHEN coalesce((payload->>'sells_fresh_produce')::boolean, false) THEN 'Fresh & Local'
    WHEN coalesce((payload->>'sells_alcohol')::boolean, false) THEN 'Local Sips'
    WHEN coalesce((payload->>'offers_sports_activities')::boolean, false) THEN 'Locally Active'
    WHEN payload->>'category' IN ('Restaurant', 'Food & Beverage', 'Local Eats') THEN 'Local Eats'
    WHEN payload->>'category' IN ('Fresh & Local', 'Local Sips', 'Locally Active') THEN payload->>'category'
    ELSE NULL END;

  FOR v_entry IN SELECT value FROM jsonb_array_elements(reviewed_deals) LOOP
    SELECT * INTO v_deal FROM public.trusted_partner_discounts
      WHERE id = NULLIF(v_entry->>'id', '')::uuid AND trusted_partner_id = v_partner;
    IF NOT FOUND OR v_deal.updated_at IS DISTINCT FROM (v_entry->>'updated_at')::timestamptz THEN
      RAISE EXCEPTION 'DEAL_REVIEW_CHANGED: A deal changed. Reload and review every deal again.';
    END IF;
    PERFORM 1 FROM public.deal_authorizations
      WHERE discount_id = v_deal.id ORDER BY id FOR UPDATE;
    IF EXISTS (
      SELECT 1 FROM public.deal_authorizations a
      WHERE a.discount_id = v_deal.id
        AND (a.status IS NULL OR a.status NOT IN ('completed', 'rejected', 'cancelled', 'expired'))
    ) OR EXISTS (
      SELECT 1 FROM public.deal_payment_attempts p
      JOIN public.deal_authorizations a ON a.id = p.deal_id
      WHERE a.discount_id = v_deal.id AND
        (p.state IN ('ready', 'submitting', 'pending', 'unknown')
         OR (p.state = 'paid' AND a.status IS DISTINCT FROM 'completed'))
    ) THEN
      RAISE EXCEPTION 'DEAL_ACTIVITY_PENDING: Resolve this deal''s requests and payments before changing it.';
    END IF;
    v_details := v_entry->'details';
    v_type := v_details->>'deal_type';
    IF jsonb_typeof(v_details) IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_details->'name') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_details->'item_name') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_details->'description') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_details->'deal_type') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_details->'deal_category') IS DISTINCT FROM 'string'
       OR nullif(trim(v_details->>'name'), '') IS NULL
       OR nullif(trim(v_details->>'item_name'), '') IS NULL
       OR v_type IS NULL OR v_type NOT IN ('standard', 'weight', 'buy_get', 'percent_item', 'free_delivery',
         'restaurant_food_percent', 'restaurant_bogo', 'restaurant_set_menu',
         'restaurant_kids_free', 'restaurant_happy_hour', 'restaurant_free_item',
         'restaurant_group', 'restaurant_birthday', 'website_redirect', 'booking_redirect')
       OR (v_expected_category IS NOT NULL AND v_details->>'deal_category' IS DISTINCT FROM v_expected_category)
       OR v_details->>'deal_category' IS NULL OR v_details->>'deal_category' NOT IN ('Food and Drink', 'Entertainment',
         'Grocery and necessities', 'Retail', 'Beauty', 'Home', 'Health and Fitness',
         'Fresh & Local', 'Local Sips', 'Local Eats', 'Locally Active', 'Other')
       OR (v_type = 'booking_redirect' AND v_expected_category IS DISTINCT FROM 'Locally Active')
       OR (v_expected_category = 'Local Eats'
           AND v_type NOT LIKE 'restaurant\_%' ESCAPE '\' AND v_type <> 'website_redirect') THEN
      RAISE EXCEPTION 'Invalid deal type or category for this partner';
    END IF;
    IF jsonb_typeof(v_details->'item_price') IS DISTINCT FROM 'number'
       OR jsonb_typeof(v_details->'percentage') IS DISTINCT FROM 'number'
       OR jsonb_typeof(v_details->'requires_manual_price') IS DISTINCT FROM 'boolean'
       OR jsonb_typeof(v_details->'is_weight_based') IS DISTINCT FROM 'boolean'
       OR jsonb_typeof(v_details->'is_bill_discount') IS DISTINCT FROM 'boolean'
       OR jsonb_typeof(v_details->'is_once_off') IS DISTINCT FROM 'boolean'
       OR jsonb_typeof(v_details->'offers_delivery') IS DISTINCT FROM 'boolean'
       OR (v_details->'fixed_amount' IS NOT NULL AND v_details->'fixed_amount' <> 'null'::jsonb
           AND jsonb_typeof(v_details->'fixed_amount') <> 'number')
       OR (v_details->'custom_data' IS NOT NULL AND v_details->'custom_data' <> 'null'::jsonb
           AND jsonb_typeof(v_details->'custom_data') <> 'object')
       OR (v_details->'bill_discount_data' IS NOT NULL AND v_details->'bill_discount_data' <> 'null'::jsonb
           AND jsonb_typeof(v_details->'bill_discount_data') <> 'object')
       OR (v_details->'schedule_data' IS NOT NULL AND v_details->'schedule_data' <> 'null'::jsonb
           AND jsonb_typeof(v_details->'schedule_data') <> 'object') THEN
      RAISE EXCEPTION 'Invalid deal field types';
    END IF;
    IF (v_details->>'item_price')::numeric < 0
       OR (v_details->>'percentage')::numeric NOT BETWEEN 0 AND 100
       OR coalesce((v_details->>'fixed_amount')::numeric, 0) < 0
       OR (v_details->>'is_weight_based')::boolean IS DISTINCT FROM (v_type = 'weight')
       OR (v_details->>'requires_manual_price')::boolean IS DISTINCT FROM (v_type = 'percent_item')
       OR ((v_details->>'is_bill_discount')::boolean AND v_type <> 'standard')
       OR ((v_details->>'is_bill_discount')::boolean AND jsonb_typeof(v_details->'bill_discount_data') IS DISTINCT FROM 'object')
       OR (NOT (v_details->>'is_bill_discount')::boolean
           AND NULLIF(v_details->'bill_discount_data', 'null'::jsonb) IS NOT NULL)
       OR (v_type IN ('standard', 'weight', 'free_delivery', 'website_redirect')
           AND NULLIF(v_details->'custom_data', 'null'::jsonb) IS NOT NULL)
       OR (v_type IN ('buy_get', 'percent_item', 'booking_redirect')
           AND jsonb_typeof(v_details->'custom_data') IS DISTINCT FROM 'object')
       OR (v_type LIKE 'restaurant\_%' ESCAPE '\'
           AND jsonb_typeof(v_details->'custom_data') IS DISTINCT FROM 'object') THEN
      RAISE EXCEPTION 'Invalid deal values';
    END IF;
    v_data := v_details->'custom_data';
    IF v_type = 'booking_redirect' AND coalesce(v_data->>'booking_url', '') !~* '^https?://' THEN
      RAISE EXCEPTION 'Invalid booking URL';
    END IF;
    IF v_type = 'buy_get' AND (
       nullif(trim(v_data->>'buy_item_name'), '') IS NULL
       OR nullif(trim(v_data->>'free_item_name'), '') IS NULL
       OR coalesce((v_data->>'buy_item_price')::numeric, 0) <= 0
       OR coalesce((v_data->>'free_item_value')::numeric, 0) <= 0
       OR (v_data->>'buy_item_price')::numeric IS DISTINCT FROM (v_details->>'item_price')::numeric
       OR (v_data->>'free_item_value')::numeric IS DISTINCT FROM (v_details->>'fixed_amount')::numeric
    ) THEN RAISE EXCEPTION 'Invalid buy-get details'; END IF;
    IF v_type = 'percent_item' AND (
       coalesce((v_data->>'percent_discount')::numeric, 0) <= 0
       OR (v_data->>'percent_discount')::numeric IS DISTINCT FROM (v_details->>'percentage')::numeric
    ) THEN RAISE EXCEPTION 'Invalid item percentage'; END IF;
    IF v_type = 'free_delivery' AND (
       (v_details->>'item_price')::numeric <= 0 OR (v_details->>'percentage')::numeric <> 0
       OR v_details->>'fixed_amount' IS NOT NULL OR (v_details->>'offers_delivery')::boolean IS NOT TRUE
    ) THEN RAISE EXCEPTION 'Invalid free-delivery details'; END IF;
    IF v_type IN ('standard', 'weight') AND NOT (v_details->>'is_bill_discount')::boolean
       AND ((v_details->>'item_price')::numeric <= 0
         OR ((v_details->>'percentage')::numeric <= 0 AND coalesce((v_details->>'fixed_amount')::numeric, 0) <= 0)
         OR coalesce((v_details->>'fixed_amount')::numeric, 0) > (v_details->>'item_price')::numeric
         OR ((v_details->>'percentage')::numeric > 0 AND coalesce((v_details->>'fixed_amount')::numeric, 0) > 0))
    THEN RAISE EXCEPTION 'Invalid discount price'; END IF;
    IF (v_details->>'is_bill_discount')::boolean THEN
      v_data := v_details->'bill_discount_data';
      IF jsonb_typeof(v_data->'isPercentage') IS DISTINCT FROM 'boolean'
         OR jsonb_typeof(v_data->'exclusions') IS DISTINCT FROM 'array'
         OR ((v_data->>'isPercentage')::boolean AND
              (coalesce((v_data->>'percentage')::numeric, 0) <= 0
               OR (v_data->>'percentage')::numeric IS DISTINCT FROM (v_details->>'percentage')::numeric))
         OR (NOT (v_data->>'isPercentage')::boolean AND
              (coalesce((v_data->>'totalDiscount')::numeric, 0) <= 0
               OR (v_data->>'totalDiscount')::numeric IS DISTINCT FROM (v_details->>'fixed_amount')::numeric))
      THEN RAISE EXCEPTION 'Invalid bill discount details'; END IF;
    END IF;
    IF v_type LIKE 'restaurant\_%' ESCAPE '\' THEN
      v_data := v_details->'custom_data';
      IF v_details->'schedule_data'->>'type' IS DISTINCT FROM 'weekly'
         OR (v_details->>'item_price')::numeric <> 0 OR v_details->>'fixed_amount' IS NOT NULL
      THEN RAISE EXCEPTION 'Invalid restaurant schedule or price'; END IF;
      IF v_type IN ('restaurant_food_percent', 'restaurant_group', 'restaurant_happy_hour')
         AND coalesce((v_data->>'percentage')::numeric, 0) NOT BETWEEN 0.000001 AND 100
      THEN RAISE EXCEPTION 'Invalid restaurant percentage'; END IF;
      IF v_type IN ('restaurant_food_percent', 'restaurant_group', 'restaurant_happy_hour')
         AND (v_data->>'percentage')::numeric IS DISTINCT FROM (v_details->>'percentage')::numeric
      THEN RAISE EXCEPTION 'Inconsistent restaurant percentage'; END IF;
      IF v_type = 'restaurant_group' AND coalesce((v_data->>'min_party_size')::integer, 0) < 2
      THEN RAISE EXCEPTION 'Invalid minimum party size'; END IF;
      IF v_type = 'restaurant_happy_hour' AND (
        jsonb_typeof(v_details->'schedule_data'->'time_slots') IS DISTINCT FROM 'array'
        OR jsonb_array_length(v_details->'schedule_data'->'time_slots') = 0)
      THEN RAISE EXCEPTION 'Happy hour requires a time slot'; END IF;
      IF v_type = 'restaurant_bogo' AND (
        nullif(trim(v_data->>'item_name'), '') IS NULL
        OR coalesce(v_data->>'pricing_mode', 'fixed') NOT IN ('fixed', 'checkout')
        OR (coalesce(v_data->>'pricing_mode', 'fixed') = 'fixed'
            AND coalesce((v_data->>'item_price')::numeric, 0) NOT BETWEEN 0.01 AND 100000)
        OR coalesce((v_data->>'buy_qty')::integer, 0) NOT BETWEEN 1 AND 200
        OR coalesce((v_data->>'free_qty')::integer, 0) NOT BETWEEN 1 AND 200
        OR coalesce((v_data->>'max_free')::integer, 0) NOT BETWEEN 0 AND 200)
      THEN RAISE EXCEPTION 'Invalid restaurant buy-get details'; END IF;
      IF v_type = 'restaurant_set_menu' AND (
        coalesce((v_data->>'set_price')::numeric, 0) <= 0
        OR coalesce((v_data->>'normal_price')::numeric, 0) <= coalesce((v_data->>'set_price')::numeric, 0))
      THEN RAISE EXCEPTION 'Invalid set menu prices'; END IF;
      IF v_type = 'restaurant_kids_free' AND coalesce((v_data->>'kid_meal_value')::numeric, 0) <= 0
      THEN RAISE EXCEPTION 'Invalid kids meal value'; END IF;
      IF v_type = 'restaurant_free_item' AND (
        nullif(trim(v_data->>'free_item_name'), '') IS NULL
        OR coalesce((v_data->>'free_item_value')::numeric, 0) <= 0)
      THEN RAISE EXCEPTION 'Invalid free item'; END IF;
      IF v_type = 'restaurant_birthday' AND (
        coalesce(v_data->>'reward', 'free_item') NOT IN ('free_item', 'percent')
        OR (v_data->>'reward' = 'percent' AND coalesce((v_data->>'percentage')::numeric, 0) NOT BETWEEN 0.000001 AND 100)
        OR (coalesce(v_data->>'reward', 'free_item') = 'free_item'
          AND (nullif(trim(v_data->>'free_item_name'), '') IS NULL OR coalesce((v_data->>'free_item_value')::numeric, 0) <= 0)))
      THEN RAISE EXCEPTION 'Invalid birthday reward'; END IF;
    END IF;
  END LOOP;

  INSERT INTO public.partner_deal_review_guard(transaction_id, partner_id)
    VALUES (txid_current(), v_partner);
  v_result := public.admin_update_trusted_partner(payload);
  IF v_result->>'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Could not update partner: %', coalesce(v_result->>'error', 'unknown error');
  END IF;
  UPDATE public.businesses SET
    sells_fresh_produce = coalesce((payload->>'sells_fresh_produce')::boolean, false),
    sells_alcohol = coalesce((payload->>'sells_alcohol')::boolean, false),
    offers_sports_activities = coalesce((payload->>'offers_sports_activities')::boolean, false)
    WHERE owner_member_id = v_partner;
  FOR v_entry IN SELECT value FROM jsonb_array_elements(reviewed_deals) LOOP
    v_details := v_entry->'details';
    UPDATE public.trusted_partner_discounts SET
      name = v_details->>'name',
      description = v_details->>'description',
      item_name = v_details->>'item_name',
      item_price = (v_details->>'item_price')::numeric,
      percentage = (v_details->>'percentage')::numeric,
      fixed_amount = (v_details->>'fixed_amount')::numeric,
      deal_type = v_details->>'deal_type',
      custom_data = NULLIF(v_details->'custom_data', 'null'::jsonb),
      requires_manual_price = (v_details->>'requires_manual_price')::boolean,
      is_weight_based = (v_details->>'is_weight_based')::boolean,
      is_bill_discount = (v_details->>'is_bill_discount')::boolean,
      is_once_off = (v_details->>'is_once_off')::boolean,
      bill_discount_data = NULLIF(v_details->'bill_discount_data', 'null'::jsonb),
      image_url = v_details->>'image_url',
      schedule_data = NULLIF(v_details->'schedule_data', 'null'::jsonb),
      deal_category = v_details->>'deal_category',
      offers_delivery = (v_details->>'offers_delivery')::boolean,
      terms_revision = gen_random_uuid(),
      updated_at = clock_timestamp()
    WHERE id = (v_entry->>'id')::uuid AND trusted_partner_id = v_partner;
  END LOOP;
  DELETE FROM public.partner_deal_review_guard
    WHERE transaction_id = txid_current() AND partner_id = v_partner;
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_partner_with_reviewed_deals(jsonb, jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_partner_with_reviewed_deals(jsonb, jsonb, jsonb) TO authenticated;

COMMIT;
