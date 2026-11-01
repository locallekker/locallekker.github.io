-- Run after migration 20261018170000. All test objects are rolled back.
BEGIN;

CREATE TEMP TABLE bogo_pricing_test_deals (deal_type TEXT, custom_data JSONB);
CREATE TRIGGER validate_bogo_test_deal
  BEFORE INSERT OR UPDATE ON bogo_pricing_test_deals
  FOR EACH ROW EXECUTE FUNCTION public.enforce_bogo_pricing_rules();

DO $$
DECLARE
  c JSONB := '{"pricing_mode":"checkout","buy_qty":1,"free_qty":1}'::JSONB;
  i JSONB;
  v_rejected BOOLEAN;
  v_case JSONB;
BEGIN
  IF public._rd_bogo_discount(c, '{"item_qty":2,"item_prices":[95,75]}', 170) <> 75
     OR public._rd_bogo_discount(c, '{"item_qty":4,"item_prices":[120,60,100,80]}', 360) <> 140
     OR public._rd_bogo_discount(c, '{"item_qty":4,"item_prices":[80,100,60,120]}', 360) <> 140
     OR public._rd_bogo_discount(c || '{"max_free":1}', '{"item_qty":4,"item_prices":[120,60,100,80]}', 360) <> 60
     OR public._rd_bogo_discount(c, '{"item_qty":3,"item_prices":[120,60,100]}', 280) <> 60
     OR public._rd_bogo_discount(c || '{"buy_qty":2}', '{"item_qty":3,"item_prices":[120,60,100]}', 280) <> 60
     OR public._rd_bogo_discount(c || '{"free_qty":2}', '{"item_qty":3,"item_prices":[120,60,100]}', 280) <> 160
     OR public._rd_bogo_discount(c, '{"item_qty":4,"item_prices":[99.95,80.10,70.05,100]}', 400) <> 150.15
     OR public._rd_bogo_discount('{"item_price":80}', '{"item_qty":2}', 160) <> 80
     OR public._rd_bogo_discount('{"pricing_mode":"fixed","item_price":80}', '{"item_qty":2,"item_prices":[95,75]}', 170) <> 80 THEN
    RAISE EXCEPTION 'BOGO calculation regression' USING ERRCODE = 'XX000';
  END IF;

  FOR i IN SELECT value FROM jsonb_array_elements('[
    {"item_qty":2},
    {"item_qty":2,"item_prices":[]},
    {"item_qty":2,"item_prices":[95]},
    {"item_qty":2,"item_prices":[95,75,60]},
    {"item_qty":2,"item_prices":[95,0]},
    {"item_qty":2,"item_prices":[95,-75]},
    {"item_qty":2,"item_prices":[95,"75"]},
    {"item_qty":2,"item_prices":[95,null]},
    {"item_qty":2,"item_prices":[95,75.001]},
    {"item_qty":2,"item_prices":[95,100001]},
    {"item_qty":2,"item_prices":[95,150]},
    {"item_qty":201,"item_prices":[]},
    {"item_qty":2.5,"item_prices":[95,75]}
  ]'::JSONB) LOOP
    v_rejected := FALSE;
    BEGIN
      PERFORM public._rd_bogo_discount(c, i, 200);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
      v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN
      RAISE EXCEPTION 'Expected invalid prices to be rejected: %', i USING ERRCODE = 'XX000';
    END IF;
  END LOOP;

  INSERT INTO bogo_pricing_test_deals VALUES
    ('restaurant_bogo', '{"item_name":"burgers","item_price":80}'),
    ('restaurant_bogo', '{"item_name":"cocktails","pricing_mode":"checkout"}'),
    ('restaurant_bogo', '{"item_name":"burgers","pricing_mode":"fixed","item_price":80}'),
    ('restaurant_food_percent', '{}');
  FOR v_case IN SELECT value FROM jsonb_array_elements('[
    {"item_name":"cocktails","pricing_mode":"invalid"},
    {"item_name":"cocktails","pricing_mode":"fixed"},
    {"item_name":"cocktails","pricing_mode":"fixed","item_price":0},
    {"item_name":"cocktails","pricing_mode":"fixed","item_price":80.001},
    {"item_name":"cocktails","pricing_mode":"checkout","buy_qty":0},
    {"item_name":"cocktails","pricing_mode":"checkout","free_qty":201},
    {"item_name":"cocktails","pricing_mode":"checkout","max_free":-1},
    {"pricing_mode":"checkout"}
  ]'::JSONB) LOOP
    v_rejected := FALSE;
    BEGIN
      INSERT INTO bogo_pricing_test_deals VALUES ('restaurant_bogo', v_case);
    EXCEPTION WHEN check_violation OR SQLSTATE 'P0001' THEN
      v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN
      RAISE EXCEPTION 'Expected invalid settings to be rejected: %', v_case USING ERRCODE = 'XX000';
    END IF;
  END LOOP;

  IF has_function_privilege('authenticated', 'public._rd_bogo_discount(jsonb,jsonb,numeric)', 'EXECUTE')
     OR has_function_privilege('anon', 'public._rd_bogo_discount(jsonb,jsonb,numeric)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.restaurant_deal_discount(uuid,uuid,jsonb,timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Internal calculator unexpectedly callable by clients' USING ERRCODE = 'XX000';
  END IF;
END;
$$;

SELECT 'BOGO SQL pricing, validation and privilege tests passed' AS result;
ROLLBACK;
