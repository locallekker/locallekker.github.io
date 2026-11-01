-- tools/check_pending_notifications.sql
-- Diagnostic SQL to validate pending deal_authorizations and notifications
-- Replace placeholders: <TP_USER_ID>, <BUSINESS_ID>, <DEAL_ID>
-- Usage (PowerShell + psql):
-- $env:PGPASSWORD = '<PG_PASSWORD>'
-- psql "postgresql://<PG_USER>@<PG_HOST>:<PG_PORT>/<PG_DB>" -f tools/check_pending_notifications.sql
--
-- Recommended: run with psql variables so you don't edit the file.
-- Example:
-- $env:PGPASSWORD = '<PG_PASSWORD>'
-- psql "postgresql://<PG_USER>@<PG_HOST>:<PG_PORT>/<PG_DB>" \
--   -v TP_USER_ID=4cd2fb8e-7971-4336-92a6-71670c689905 \
--   -v BUSINESS_ID=123e4567-e89b-12d3-a456-426614174000 \
--   -v DEAL_ID=9f1b3d2a-0000-0000-0000-000000000000 \
--   -f tools/check_pending_notifications.sql

-- -----------------------------------------------------------------------------
-- 0) Quick info header: show current_time and current_user
-- -----------------------------------------------------------------------------
SELECT now() AS now, current_user AS pg_user;

-- -----------------------------------------------------------------------------
-- 1) List all pending deal_authorizations (global)
-- -----------------------------------------------------------------------------
SELECT id,
       business_id,
       trusted_partner_id,
       member_id,
       amount,
       status,
       created_at
FROM deal_authorizations
WHERE status = 'pending'
ORDER BY created_at DESC;

-- -----------------------------------------------------------------------------
-- 2) Pending counts grouped by business and trusted partner
-- -----------------------------------------------------------------------------
SELECT business_id,
       trusted_partner_id,
       COUNT(*) AS pending_count
FROM deal_authorizations
WHERE status = 'pending'
GROUP BY business_id, trusted_partner_id
ORDER BY pending_count DESC;

-- -----------------------------------------------------------------------------
-- 3) Pending authorizations for a single trusted partner user
--    REPLACE <TP_USER_ID> with the trusted partner's user id (owner_member_id)
-- -----------------------------------------------------------------------------
-- Example: WHERE status = 'pending' AND trusted_partner_id = '4cd2fb8e-7971-4336-92a6-71670c689905'
SELECT id, business_id, member_id, amount, created_at
FROM deal_authorizations
WHERE status = 'pending'
  AND trusted_partner_id = :'TP_USER_ID'::uuid
ORDER BY created_at DESC;

-- -----------------------------------------------------------------------------
-- 4) Pending authorizations for a single business
--    REPLACE <BUSINESS_ID>
-- -----------------------------------------------------------------------------
SELECT id, trusted_partner_id, member_id, amount, created_at
FROM deal_authorizations
WHERE status = 'pending'
  AND business_id = :'BUSINESS_ID'::uuid
ORDER BY created_at DESC;

-- -----------------------------------------------------------------------------
-- 5) List existing notifications of type 'deal_request'
--    Shows notifications and their JSON data key deal_authorization_id
-- -----------------------------------------------------------------------------
SELECT id,
       user_id,
       created_at,
       is_read,
       data->>'deal_authorization_id' AS deal_authorization_id,
       data
FROM notifications
WHERE type = 'deal_request'
ORDER BY created_at DESC;

-- -----------------------------------------------------------------------------
-- 6) Pending deal_authorizations with NO corresponding notification (core test)
--    Uses explicit cast of JSON value to uuid to match da.id
-- -----------------------------------------------------------------------------
SELECT da.id AS deal_id,
       da.business_id,
       da.trusted_partner_id,
       da.member_id,
       da.amount,
       da.created_at
FROM deal_authorizations da
LEFT JOIN notifications n
  ON (n.data->>'deal_authorization_id')::uuid = da.id
  AND n.type = 'deal_request'
WHERE da.status = 'pending'
  AND n.id IS NULL
ORDER BY da.created_at DESC;

-- -----------------------------------------------------------------------------
-- 7) Notifications referencing non-existent deal_authorizations
-- -----------------------------------------------------------------------------
SELECT n.id AS notification_id,
       n.user_id,
       n.created_at,
       n.data->>'deal_authorization_id' AS referenced_deal_id
FROM notifications n
LEFT JOIN deal_authorizations da
  ON da.id = (n.data->>'deal_authorization_id')::uuid
WHERE n.type = 'deal_request'
  AND da.id IS NULL
ORDER BY n.created_at DESC;

-- -----------------------------------------------------------------------------
-- 8) For a specific trusted partner: pending authorizations and notification id (side-by-side)
--    REPLACE <TP_USER_ID>
-- -----------------------------------------------------------------------------
WITH pending AS (
  SELECT id, business_id, member_id, amount, created_at
  FROM deal_authorizations
  WHERE status = 'pending' AND trusted_partner_id = :'TP_USER_ID'::uuid
),
notifs AS (
  SELECT (data->>'deal_authorization_id') AS deal_id, id AS notification_id
  FROM notifications
  WHERE type = 'deal_request' AND user_id = :'TP_USER_ID'::uuid
)
SELECT p.id AS deal_id,
       p.business_id,
       p.member_id,
       p.amount,
       p.created_at,
       n.notification_id
FROM pending p
LEFT JOIN notifs n ON n.deal_id = p.id
ORDER BY p.created_at DESC;

-- -----------------------------------------------------------------------------
-- 9) Verify the RPC function create_notification_bypass_rls exists
-- -----------------------------------------------------------------------------
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_name = 'create_notification_bypass_rls';

-- Alternative check in pg_proc (shows source if you are owner)
SELECT p.proname, pg_get_functiondef(p.oid) AS ddl
FROM pg_proc p
WHERE p.proname = 'create_notification_bypass_rls';

-- -----------------------------------------------------------------------------
-- 10) Inspect RLS policies for key tables
--     Shows policy name, command (r/w/a/d), using and with check expressions
-- -----------------------------------------------------------------------------
SELECT tab.relname AS table_name,
       p.polname AS policy_name,
       p.polcmd AS command,
       pg_get_userbyid(p.polrole) AS policy_owner,
       pg_get_expr(p.polqual, p.polrelid) AS using_expression,
       pg_get_expr(p.polwithcheck, p.polrelid) AS with_check_expression
FROM pg_policy p
JOIN pg_class tab ON p.polrelid = tab.oid
WHERE tab.relname IN ('profiles','notifications','deal_authorizations','businesses')
ORDER BY tab.relname, p.polname;

-- -----------------------------------------------------------------------------
-- 11) Check businesses lookup for the trusted partner user
--     REPLACE <TP_USER_ID>
-- -----------------------------------------------------------------------------
SELECT id, owner_member_id, name
FROM businesses
WHERE owner_member_id = :'TP_USER_ID'::uuid;

-- -----------------------------------------------------------------------------
-- 12) Count notifications grouped by user (distribution check)
-- -----------------------------------------------------------------------------
SELECT user_id, COUNT(*) AS notification_count
FROM notifications
WHERE type = 'deal_request'
GROUP BY user_id
ORDER BY notification_count DESC;

-- -----------------------------------------------------------------------------
-- 13) One-shot backfill check for a TP: pending without notifications
--     REPLACE <TP_USER_ID>
-- -----------------------------------------------------------------------------
SELECT da.id AS deal_id
FROM deal_authorizations da
LEFT JOIN notifications n
  ON (n.data->>'deal_authorization_id')::uuid = da.id
  AND n.type = 'deal_request'
WHERE da.status = 'pending'
  AND da.trusted_partner_id = :'TP_USER_ID'::uuid
  AND n.id IS NULL;

-- -----------------------------------------------------------------------------
-- 14) Manual insert template (run as DB owner or via RPC) - REPLACE placeholders
--     Uncomment and run manually if you want to test an insert as admin (may require superuser/owner)
-- -----------------------------------------------------------------------------
-- INSERT INTO notifications (user_id, title, message, type, data, is_read, created_at)
-- VALUES (
--   :'TP_USER_ID'::uuid,
--   'Test Deal Request',
--   'Manual test notification',
--   'deal_request',
--   jsonb_build_object('deal_authorization_id', :'DEAL_ID'::text),
--   false,
--   now()
-- ) RETURNING id;

-- -----------------------------------------------------------------------------
-- 15) Quick sanity summary: pending total, deal_request notifications total, pending missing notifications
-- -----------------------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM deal_authorizations WHERE status = 'pending') AS pending_total,
  (SELECT COUNT(*) FROM notifications WHERE type = 'deal_request') AS deal_request_notifications_total,
  (SELECT COUNT(*) FROM (
     SELECT da.id FROM deal_authorizations da
     LEFT JOIN notifications n
       ON (n.data->>'deal_authorization_id')::uuid = da.id
       AND n.type = 'deal_request'
     WHERE da.status = 'pending' AND n.id IS NULL
  ) t) AS pending_without_notifications;

-- End of file
