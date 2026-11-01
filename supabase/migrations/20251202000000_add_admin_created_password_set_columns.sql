-- Baseline alias migration for production registry alignment.
-- Production history contains version 20251202000000 for this change,
-- while repo contains earlier equivalent migration(s).
--
-- Intentionally no-op: canonical schema change logic lives in:
--   20251125100512_add_admin_created_password_set_columns.sql

BEGIN;

-- no-op baseline marker
SELECT 'baseline alias: 20251202000000_add_admin_created_password_set_columns' AS info;

COMMIT;
