-- Run only against a disposable, migrated database: supabase test db.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET LOCAL search_path = public, extensions;
SELECT plan(25);
SELECT is(has_table_privilege('authenticated', 'public.deal_detail_views', 'INSERT'),
  FALSE, 'View events cannot be inserted directly');
SELECT is(has_function_privilege('anon', 'public.record_deal_detail_view(uuid)', 'EXECUTE'),
  FALSE, 'Anonymous users cannot invoke tracking RPC');

INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'analytics-member@example.test', '{"role":"member"}'),
  ('a0000000-0000-0000-0000-000000000002', 'analytics-partner@example.test', '{"role":"trusted_partner"}'),
  ('a0000000-0000-0000-0000-000000000003', 'analytics-admin@example.test', '{"role":"admin"}');

INSERT INTO public.profiles (id, role, subscription, created_at) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'member', 'active', '2099-01-10Z'),
  ('a0000000-0000-0000-0000-000000000002', 'trusted_partner', 'inactive', '2099-01-10Z'),
  ('a0000000-0000-0000-0000-000000000003', 'admin', 'inactive', '2099-01-10Z')
ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role,
  subscription = EXCLUDED.subscription, created_at = EXCLUDED.created_at;
INSERT INTO public.memberships (user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'member'),
  ('a0000000-0000-0000-0000-000000000002', 'trusted_partner'),
  ('a0000000-0000-0000-0000-000000000003', 'admin')
ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role;

INSERT INTO public.businesses (id, owner_member_id, name) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', 'Analytics fixture');
INSERT INTO public.trusted_partner_discounts (
  id, trusted_partner_id, business_id, name, item_name, item_price, percentage, deal_type, is_active
) VALUES (
  'd0000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000002',
  'b0000000-0000-0000-0000-000000000001',
  'Fixture offer', 'Fixture item', 100, 20, 'percent_item', TRUE
);
INSERT INTO public.deal_authorizations (
  member_id, business_id, discount_id, status, payment_method, amount, created_at, completed_at
) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'completed', 'pos', 80, '2099-01-10Z', '2099-01-11Z'),
  ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'approved', 'in_app', 9999, '2099-01-10Z', NULL),
  ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'completed', 'in_app', 100, '2099-01-10Z', '2099-02-01Z'),
  ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'completed', 'pos', NULL, '2099-01-10Z', '2099-01-11Z');
INSERT INTO public.payments (member_id, amount, status, created_at, happened_at) VALUES
  ('a0000000-0000-0000-0000-000000000001', 15, 'completed', '2099-01-10Z', '2099-01-10Z'),
  ('a0000000-0000-0000-0000-000000000001', 9999, 'pending', '2099-01-10Z', '2099-01-10Z');

SELECT set_config('request.jwt.claim.sub', '', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"anon"}', TRUE);
SELECT throws_ok(
  $$SELECT public.get_admin_engagement_report('2099-01-01Z', '2099-02-01Z')$$,
  '42501', 'Admin access required', 'Anonymous reporting denied'
);

SELECT set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"a0000000-0000-0000-0000-000000000001"}', TRUE);
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$SELECT public.get_admin_engagement_report('2099-01-01Z', '2099-02-01Z')$$,
  '42501', 'Admin access required', 'Member reporting denied'
);
SELECT lives_ok(
  $$SELECT public.record_deal_detail_view('d0000000-0000-0000-0000-000000000001')$$,
  'Member can record an intentional deal open'
);
SELECT public.record_deal_detail_view('d0000000-0000-0000-0000-000000000001');
SELECT is((SELECT count(*) FROM public.deal_detail_views), 0::BIGINT, 'Members cannot read raw view events');
SELECT throws_ok(
  $$SELECT public.record_deal_detail_view('d0000000-0000-0000-0000-000000000099')$$,
  '22023', 'Active deal not found', 'Invalid deal is explicitly rejected'
);
RESET ROLE;
SELECT is(
  (SELECT count(*) FROM public.deal_detail_views WHERE deal_id = 'd0000000-0000-0000-0000-000000000001'),
  1::BIGINT, 'Repeat member opens deduplicated in a bucket'
);
UPDATE public.deal_detail_views SET viewed_at = '2099-01-10Z'
WHERE deal_id = 'd0000000-0000-0000-0000-000000000001';
INSERT INTO public.deal_detail_views (deal_id, member_id, viewed_at, view_bucket) VALUES
  ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '2099-01-11Z', 999999999),
  ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '2099-02-01Z', 999999998);

SELECT set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"a0000000-0000-0000-0000-000000000002"}', TRUE);
SELECT public.record_deal_detail_view('d0000000-0000-0000-0000-000000000001');
SELECT is(
  (SELECT count(*) FROM public.deal_detail_views WHERE member_id = 'a0000000-0000-0000-0000-000000000002'),
  0::BIGINT, 'Partner browsing is excluded'
);

SELECT set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', TRUE);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"a0000000-0000-0000-0000-000000000003"}', TRUE);
SELECT public.record_deal_detail_view('d0000000-0000-0000-0000-000000000001');
SELECT is(
  (SELECT count(*) FROM public.deal_detail_views WHERE member_id = 'a0000000-0000-0000-0000-000000000003'),
  0::BIGINT, 'Admin previews are excluded'
);
SELECT throws_ok(
  $$SELECT public.get_admin_engagement_report('2099-02-01Z', '2099-01-01Z')$$,
  '22023', 'Invalid reporting period', 'Reversed range rejected'
);
CREATE TEMP TABLE analytics_result AS
  SELECT public.get_admin_engagement_report('2099-01-01Z', '2099-02-01Z') AS report;
SELECT is((SELECT (report->>'member_signups')::INT FROM analytics_result), 1, 'Member signup count');
SELECT is((SELECT (report->>'partner_signups')::INT FROM analytics_result), 1, 'Partner signup count');
SELECT is((
  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'partner_terms_accepted'
  ) THEN report->>'ready_partner_signups' = '0'
    ELSE report->'ready_partner_signups' = 'null'::JSONB END
  FROM analytics_result
), TRUE, 'Partner terms status is explicit on both current and legacy schemas');
SELECT is((SELECT (report->>'subscription_sales')::NUMERIC FROM analytics_result), 15::NUMERIC, 'Only completed platform payments counted');
SELECT is((SELECT (report->>'deal_sales')::NUMERIC FROM analytics_result), 80::NUMERIC, 'Approvals and end-boundary completions excluded from sales');
SELECT is((SELECT (report->>'redemptions')::INT FROM analytics_result), 2, 'Completed deals counted even when amount missing');
SELECT is((SELECT (report->>'missing_amounts')::INT FROM analytics_result), 1, 'Missing sale amounts surfaced');
SELECT is((SELECT (report->>'views')::INT FROM analytics_result), 2, 'View period excludes exact end boundary');
SELECT is((SELECT (report->>'viewers')::INT FROM analytics_result), 1, 'Unique viewers not inflated by repeat opens');
SELECT is((
  SELECT (p->'deals'->0->>'redemptions')::INT
  FROM analytics_result, jsonb_array_elements(report->'partners') p
  WHERE p->>'partner_id' = 'a0000000-0000-0000-0000-000000000002'
), 2, 'Deals attributed to partner owner, not business UUID');

-- All schema/data changes below roll back with the disposable test transaction.
ALTER TABLE public.payments DROP COLUMN happened_at;
SELECT is((
  SELECT (public.get_admin_engagement_report('2099-01-01Z', '2099-02-01Z')->>'subscription_sales')::NUMERIC
), 15::NUMERIC, 'Payments without optional timestamps use creation date');
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;
UPDATE public.payments SET completed_at = '2099-02-01Z'
WHERE member_id = 'a0000000-0000-0000-0000-000000000001' AND status = 'completed';
SELECT is((
  SELECT (public.get_admin_engagement_report('2099-01-01Z', '2099-02-01Z')->>'subscription_sales')::NUMERIC
), 0::NUMERIC, 'Completion date overrides creation date without happened_at');
SELECT is((
  SELECT (public.get_admin_engagement_report('2099-02-01Z', '2099-03-01Z')->>'subscription_sales')::NUMERIC
), 15::NUMERIC, 'Completion at start boundary is included without happened_at');
ALTER TABLE public.payments ADD COLUMN happened_at TIMESTAMPTZ;
UPDATE public.payments SET happened_at = '2099-01-10Z'
WHERE member_id = 'a0000000-0000-0000-0000-000000000001' AND status = 'completed';
SELECT is((
  SELECT (public.get_admin_engagement_report('2099-01-01Z', '2099-02-01Z')->>'subscription_sales')::NUMERIC
), 0::NUMERIC, 'Completion date takes precedence when both timestamp columns exist');

SELECT * FROM finish();
ROLLBACK;
