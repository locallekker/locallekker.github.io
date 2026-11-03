-- Run only against a disposable, migrated database: supabase test db.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET LOCAL search_path = public, extensions;
SELECT plan(12);

SELECT is(has_table_privilege('anon', 'public.guest_deal_request_attempts', 'SELECT'),
  false, 'Guests cannot read request attempts directly');
SELECT is(has_table_privilege('authenticated', 'public.guest_visitors', 'SELECT'),
  false, 'Members cannot read guest visitors directly');
SELECT is(has_function_privilege('anon', 'public.record_guest_deal_request(uuid, uuid, numeric)', 'EXECUTE'),
  true, 'Guests can record deal request attempts');
SELECT is(has_function_privilege('anon', 'public.link_guest_conversion(uuid)', 'EXECUTE'),
  false, 'Guests cannot claim conversions');
SELECT is(has_function_privilege('anon', 'public.get_admin_guest_conversion_report(timestamptz, timestamptz)', 'EXECUTE'),
  false, 'Guests cannot read the admin report');

INSERT INTO auth.users (id, email, created_at) VALUES
  ('a2000000-0000-0000-0000-000000000001', 'guest-conv-partner@example.test', now() - interval '1 year'),
  ('a2000000-0000-0000-0000-000000000002', 'guest-conv-new@example.test', now() + interval '1 minute');
INSERT INTO public.businesses (id, owner_member_id, name)
VALUES ('b2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001',
  'Conversion Fixture');
INSERT INTO public.trusted_partner_discounts (id, trusted_partner_id, business_id, name, percentage, is_active)
VALUES
  ('d2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001',
   'b2000000-0000-0000-0000-000000000001', 'Conversion fixture deal', 10, true),
  ('d2000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000001',
   'b2000000-0000-0000-0000-000000000001', 'Inactive fixture deal', 10, false);

SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SELECT public.record_guest_visit('c2000000-0000-0000-0000-000000000001');
SELECT public.record_guest_deal_request('c2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 25);
SELECT public.record_guest_deal_request('c2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 25);
SELECT public.record_guest_deal_request('c2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000002', 25);
RESET ROLE;

SELECT is((SELECT count(*) FROM public.guest_deal_request_attempts
           WHERE guest_id = 'c2000000-0000-0000-0000-000000000001'),
  1::bigint, 'Double taps and inactive deals are not counted');
SELECT is((SELECT potential_savings FROM public.guest_deal_request_attempts
           WHERE guest_id = 'c2000000-0000-0000-0000-000000000001'),
  25.00::numeric, 'Shown savings are stored with the attempt');

SELECT set_config('request.jwt.claims',
  '{"sub":"a2000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
SELECT is(public.link_guest_conversion('c2000000-0000-0000-0000-000000000001'),
  'signup', 'Accounts created after browsing count as signups');
SELECT is(public.link_guest_conversion('c2000000-0000-0000-0000-000000000001'),
  NULL, 'A guest id converts only once');
SELECT throws_ok(
  $$SELECT public.get_admin_guest_conversion_report(now() - interval '1 day', now() + interval '1 day')$$,
  '42501', NULL, 'Non-admin members cannot read the report');
RESET ROLE;

SELECT set_config('request.jwt.claims',
  '{"sub":"a2000000-0000-0000-0000-000000000002","role":"authenticated","app_metadata":{"role":"admin"}}', true);
SET LOCAL ROLE authenticated;
SELECT is(
  (public.get_admin_guest_conversion_report(now() - interval '1 day', now() + interval '1 day')
    ->> 'signup_conversions')::int >= 1,
  true, 'Admin report includes signup conversions');
SELECT ok(
  public.get_admin_guest_conversion_report(now() - interval '1 day', now() + interval '1 day')
    -> 'deals' @> '[{"deal_name":"Conversion fixture deal","business_name":"Conversion Fixture"}]',
  'Admin report lists the requested deal and partner');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
