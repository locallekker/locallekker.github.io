-- Fix: deal_authorizations rows with NULL discount_id break the
-- trusted partner authorization list (DealAuthorization.fromJson rejected
-- them, aborting the whole fetch).
--
-- Confirmed inspection (2026-05-13): only 5 legacy test rows had NULL
-- discount_id, all already in 'rejected' or 'completed' status. They are
-- being deleted so the column can be made NOT NULL going forward.
--
-- Run steps individually in the Supabase SQL editor and verify after each.

-- 1. Inspect (should be 0 rows after step 2):
SELECT id, member_id, business_id, trusted_partner_id, status, created_at, notes
FROM deal_authorizations
WHERE discount_id IS NULL
ORDER BY created_at DESC;

-- 2. Delete legacy NULL rows (test data, all rejected/completed).
DELETE FROM deal_authorizations
WHERE discount_id IS NULL;

-- 3. Enforce NOT NULL to prevent recurrence.
ALTER TABLE deal_authorizations
  ALTER COLUMN discount_id SET NOT NULL;
