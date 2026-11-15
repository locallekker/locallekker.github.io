-- Run only against a disposable migrated Supabase database.
BEGIN;
SELECT '1..1' AS tap;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
INSERT INTO auth.users(id, email, raw_user_meta_data) VALUES
  ('ce100000-0000-0000-0000-000000000001', 'review-admin@example.test', '{}'),
  ('ce100000-0000-0000-0000-000000000002', 'review-partner@example.test', '{}'),
  ('ce100000-0000-0000-0000-000000000003', 'review-member@example.test', '{}');
INSERT INTO public.profiles(id, email, name, surname, role) VALUES
  ('ce100000-0000-0000-0000-000000000001', 'review-admin@example.test', 'Review', 'Admin', 'admin'),
  ('ce100000-0000-0000-0000-000000000002', 'review-partner@example.test', 'Review', 'Partner', 'trusted_partner'),
  ('ce100000-0000-0000-0000-000000000003', 'review-member@example.test', 'Review', 'Member', 'member')
ON CONFLICT(id) DO UPDATE SET email = EXCLUDED.email, role = EXCLUDED.role;
INSERT INTO public.memberships(user_id, role)
VALUES ('ce100000-0000-0000-0000-000000000001', 'admin')
ON CONFLICT(user_id) DO UPDATE SET role = EXCLUDED.role;
SELECT set_config('request.jwt.claim.sub', 'ce100000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"ce100000-0000-0000-0000-000000000001","role":"authenticated"}', true);

DO $$
DECLARE
  v_partner uuid := 'ce100000-0000-0000-0000-000000000002';
  v_member uuid := 'ce100000-0000-0000-0000-000000000003';
  v_business uuid := gen_random_uuid();
  v_discount uuid := gen_random_uuid();
  v_request uuid := gen_random_uuid();
  v_updated timestamptz;
  v_revision uuid;
  v_payload jsonb := jsonb_build_object(
    'partner_id', v_partner, 'name', 'Review', 'surname', 'Partner',
    'email', 'review-partner@example.test', 'business_name', 'Review fixture',
    'category', 'Retail', 'sells_fresh_produce', true, 'sells_alcohol', false,
    'offers_sports_activities', false
  );
  v_expected jsonb := jsonb_build_object(
    'category', 'Retail', 'sells_fresh_produce', false,
    'sells_alcohol', false, 'offers_sports_activities', false
  );
  v_details jsonb := jsonb_build_object(
    'name', 'Reviewed deal', 'description', 'Reviewed', 'item_name', 'Item',
    'item_price', 100, 'percentage', 20, 'fixed_amount', null, 'deal_type', 'standard',
    'custom_data', null, 'requires_manual_price', false, 'is_weight_based', false,
    'is_bill_discount', false, 'is_once_off', false, 'bill_discount_data', null,
    'image_url', null, 'schedule_data', null, 'deal_category', 'Fresh & Local',
    'offers_delivery', false
  );
  v_review jsonb;
BEGIN
  INSERT INTO public.businesses(id, owner_member_id, name, category)
  VALUES (v_business, v_partner, 'Review fixture', 'Retail');
  INSERT INTO public.trusted_partner_discounts(
    id, business_id, trusted_partner_id, name, description, item_name,
    item_price, percentage, deal_type, deal_category
  ) VALUES (v_discount, v_business, v_partner, 'Original', 'Original', 'Item',
    100, 10, 'standard', 'Retail')
  RETURNING updated_at INTO v_updated;
  v_review := jsonb_build_array(jsonb_build_object(
    'id', v_discount, 'updated_at', v_updated, 'details', v_details
  ));

  BEGIN
    UPDATE public.businesses SET category = 'Restaurant' WHERE id = v_business;
    RAISE EXCEPTION 'Category changed without reviewing deals';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'PARTNER_DEAL_REVIEW_REQUIRED:%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.admin_update_partner_with_reviewed_deals(v_payload, '[]', v_expected);
    RAISE EXCEPTION 'Incomplete deal review was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'DEAL_REVIEW_CHANGED:%' THEN RAISE; END IF;
  END;

  INSERT INTO public.deal_authorizations(
    id, member_id, business_id, trusted_partner_id, discount_id, status,
    authorization_type, payment_method, amount, deal_snapshot
  ) VALUES (v_request, v_member, v_business, v_partner, v_discount, 'pending',
    'in_store', 'pos', 90, '{}'::jsonb);
  BEGIN
    PERFORM public.admin_update_partner_with_reviewed_deals(v_payload, v_review, v_expected);
    RAISE EXCEPTION 'Pending request did not block conversion';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'DEAL_ACTIVITY_PENDING:%' THEN RAISE; END IF;
  END;
  DELETE FROM public.deal_authorizations WHERE id = v_request;

  PERFORM public.admin_update_partner_with_reviewed_deals(v_payload, v_review, v_expected);
  SELECT terms_revision INTO v_revision
    FROM public.trusted_partner_discounts WHERE id = v_discount;
  IF v_revision IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.trusted_partner_discounts
    WHERE id = v_discount AND deal_category = 'Fresh & Local'
      AND custom_data IS NULL AND bill_discount_data IS NULL
  ) THEN
    RAISE EXCEPTION 'Reviewed deal was not converted correctly';
  END IF;
  BEGIN
    INSERT INTO public.deal_authorizations(
      id, member_id, business_id, trusted_partner_id, discount_id, status,
      authorization_type, payment_method, amount, deal_snapshot
    ) VALUES (gen_random_uuid(), v_member, v_business, v_partner, v_discount,
      'pending', 'in_store', 'pos', 90, '{}'::jsonb);
    RAISE EXCEPTION 'Stale request was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'DEAL_TERMS_CHANGED:%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.trusted_partner_discounts SET name = 'Stale edit' WHERE id = v_discount;
    RAISE EXCEPTION 'Stale edit was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'DEAL_TERMS_CHANGED:%' THEN RAISE; END IF;
  END;
END;
$$;
SELECT 'ok 1 - category review is atomic and rejects unresolved and stale requests' AS tap;
ROLLBACK;
