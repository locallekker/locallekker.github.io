-- Baseline alias migration for production registry alignment.
-- Production history contains version 20251202000001 for this change,
-- while repo contains earlier equivalent migration(s).
--
-- Intentionally no-op: canonical trigger update logic lives in:
--   20251125100511_update_trigger_for_trusted_partner.sql

BEGIN;

-- no-op baseline marker
SELECT 'baseline alias: 20251202000001_update_trigger_for_trusted_partner' AS info;

COMMIT;
