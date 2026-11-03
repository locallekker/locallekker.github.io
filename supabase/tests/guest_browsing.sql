-- Run only against a disposable, migrated database: supabase test db.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET LOCAL search_path = public, extensions;
SELECT plan(11);

SELECT is(has_table_privilege('anon', 'public.guest_business_catalogue', 'SELECT'),
  true, 'Guests can read the public business projection');
SELECT is(has_table_privilege('anon', 'public.guest_business_catalogue', 'INSERT'),
  false, 'Guests cannot insert through the projection');
SELECT is(has_table_privilege('anon', 'public.guest_business_catalogue', 'UPDATE'),
  false, 'Guests cannot update through the projection');
SELECT is(has_table_privilege('anon', 'public.guest_business_catalogue', 'DELETE'),
  false, 'Guests cannot delete through the projection');
SELECT is(has_function_privilege('anon', 'public.discount_accepts_in_app_payment(uuid)', 'EXECUTE'),
  true, 'Guests can check payment availability without reading bank accounts');
SELECT is(
  (SELECT count(*) FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'guest_business_catalogue'
     AND column_name IN ('bank_account_number', 'paystack_subaccount_code', 'tax_number', 'liquor_license_url')),
  0::bigint, 'Private business fields are not projected');

INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('a1000000-0000-0000-0000-000000000001', 'guest-fixture-partner@example.test', '{"role":"trusted_partner"}'),
  ('a1000000-0000-0000-0000-000000000002', 'guest-fixture-hidden@example.test', '{"role":"trusted_partner"}');
INSERT INTO public.businesses (id, owner_member_id, name) VALUES
  ('b1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'Guest public fixture'),
  ('b1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000002', 'Guest hidden fixture');
INSERT INTO public.trusted_partner_discounts (
  id, trusted_partner_id, business_id, name, item_name, item_price, percentage, deal_type, is_active
) VALUES
  ('d1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001', 'Guest active fixture', 'Item', 200, 25, 'standard', true),
  ('d1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000002',
   'b1000000-0000-0000-0000-000000000002', 'Guest inactive fixture', 'Item', 200, 25, 'standard', false);

SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SELECT set_config('request.headers', '{"x-ll-capabilities":"restaurant_deals_v1"}', true);
SET LOCAL ROLE anon;

SELECT is(
  (SELECT name FROM public.guest_business_catalogue WHERE id = 'b1000000-0000-0000-0000-000000000001'),
  'Guest public fixture', 'Guests see business names for active deals');
SELECT is(
  (SELECT count(*) FROM public.guest_business_catalogue WHERE id = 'b1000000-0000-0000-0000-000000000002'),
  0::bigint, 'Businesses without active deals are hidden');
SELECT is(
  (SELECT count(*) FROM public.trusted_partner_discounts
   WHERE id IN ('d1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002')),
  1::bigint, 'Guests see active deals only');
SELECT throws_ok(
  $$INSERT INTO public.deal_authorizations (member_id, discount_id, business_id, amount, payment_method, status)
    VALUES ('a1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
    'b1000000-0000-0000-0000-000000000001', 150, 'pos', 'pending')$$,
  '42501', null, 'Guests cannot submit authorizations');
RESET ROLE;

SELECT is(
  (SELECT count(*) FROM public.businesses WHERE id = 'b1000000-0000-0000-0000-000000000002'),
  1::bigint, 'Guest visibility does not remove existing business data');

SELECT * FROM finish();
ROLLBACK;
