-- Backfill denormalized member_name / business_name / member_email on existing deal_receipts.
--
-- Why: deal_receipts stores names denormalized at capture time. Receipts created
-- before the name-resolution fix may contain blanks or generic placeholders
-- ("Unknown Member", "Member", "Business", "N/A"). This script repairs those rows
-- so existing members' names and the trusted-partner business name display correctly.
--
-- Safety:
--  * Idempotent / re-runnable: only updates rows whose stored value is missing or a
--    known placeholder. Rows that already have a real value are left untouched.
--  * No deletes. Reversible by restoring from a backup if ever needed.
--  * Run in the Supabase SQL editor and review the verification queries at the bottom.

BEGIN;

-- 1) Ensure member_email is populated from profiles where missing (used as a fallback).
UPDATE public.deal_receipts dr
SET member_email = p.email,
    updated_at = NOW()
FROM public.profiles p
WHERE p.id = dr.member_id
  AND (dr.member_email IS NULL OR TRIM(dr.member_email) = '')
  AND p.email IS NOT NULL
  AND TRIM(p.email) <> '';

-- 2) Backfill member_name from profiles (name + surname) where missing/placeholder.
UPDATE public.deal_receipts dr
SET member_name = TRIM(COALESCE(p.name, '') || ' ' || COALESCE(p.surname, '')),
    updated_at = NOW()
FROM public.profiles p
WHERE p.id = dr.member_id
  AND TRIM(COALESCE(p.name, '') || ' ' || COALESCE(p.surname, '')) <> ''
  AND (
    dr.member_name IS NULL
    OR TRIM(dr.member_name) = ''
    OR dr.member_name IN ('Unknown Member', 'Unknown user', 'Member', 'N/A')
  );

-- 3) Where the profile has no name, fall back to the member email.
UPDATE public.deal_receipts dr
SET member_name = COALESCE(NULLIF(TRIM(dr.member_email), ''), p.email),
    updated_at = NOW()
FROM public.profiles p
WHERE p.id = dr.member_id
  AND (
    dr.member_name IS NULL
    OR TRIM(dr.member_name) = ''
    OR dr.member_name IN ('Unknown Member', 'Unknown user', 'Member', 'N/A')
  )
  AND COALESCE(NULLIF(TRIM(dr.member_email), ''), p.email) IS NOT NULL;

-- 4) Backfill business_name from the businesses table where missing/placeholder.
UPDATE public.deal_receipts dr
SET business_name = b.name,
    updated_at = NOW()
FROM public.businesses b
WHERE b.id = dr.business_id
  AND b.name IS NOT NULL
  AND TRIM(b.name) <> ''
  AND (
    dr.business_name IS NULL
    OR TRIM(dr.business_name) = ''
    OR dr.business_name IN ('Business', 'Trusted Partner', 'N/A')
  );

COMMIT;

-- ==========================
-- Verification queries (run after the COMMIT to confirm no rows remain unresolved)
-- ==========================

-- Receipts still missing a usable member name:
-- SELECT id, receipt_number, member_id, member_name, member_email
-- FROM public.deal_receipts
-- WHERE member_name IS NULL
--    OR TRIM(member_name) = ''
--    OR member_name IN ('Unknown Member', 'Unknown user', 'Member', 'N/A');

-- Receipts still missing a usable business name (excluding bill receipts with no business_id):
-- SELECT id, receipt_number, business_id, business_name
-- FROM public.deal_receipts
-- WHERE business_id IS NOT NULL
--   AND (business_name IS NULL
--        OR TRIM(business_name) = ''
--        OR business_name IN ('Business', 'Trusted Partner', 'N/A'));
