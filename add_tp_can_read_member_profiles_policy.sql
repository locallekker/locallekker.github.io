-- ============================================================
-- COMPREHENSIVE FIX: TP member names in deal requests & receipts
-- ============================================================
--
-- Problem: When a TP member (e.g. Miss Shein) requests a deal from a TP
-- (e.g. Wansley), the TP dashboard shows "Member" instead of the real name
-- in ALL three places:
--   1. Pending deal requests tab
--   2. Approved deal requests tab
--   3. Receipt books (TP side and member side)
--
-- Root cause:
--   (a) LIVE QUERIES (pending/approved tabs, new receipt creation) –
--       The Supabase join from deal_authorizations → profiles is blocked by
--       the existing RLS policy that only lets a user read their own profile.
--       When the TP fetches deal authorizations, the joined profile comes back
--       null → buildMemberDisplayName falls back to "Member".
--   (b) EXISTING RECEIPT ROWS – deal_receipts.member_name was already written
--       as "Member" / "" for receipts created before this fix. These need to
--       be backfilled from the profiles table.
--
-- This script is idempotent / re-runnable.
-- Run it in the Supabase SQL editor once. No app code changes needed.
-- ============================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────
-- PART 1: RLS policy so TPs can read member profiles
-- Fixes: pending tab, approved tab, and name capture in all
--        new receipt creation paths (deal_approval_popup_service,
--        deal_authorization_service, receipt_generator_page).
-- ─────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "TPs can read profiles of members with deal authorizations"
  ON public.profiles;

CREATE POLICY "TPs can read profiles of members with deal authorizations"
ON public.profiles
FOR SELECT
USING (
  -- The viewer must own a business that has a deal authorization from this profile
  EXISTS (
    SELECT 1
    FROM public.deal_authorizations da
    JOIN public.businesses b ON b.id = da.business_id
    WHERE da.member_id = profiles.id
      AND b.owner_member_id = auth.uid()
  )
);

-- ─────────────────────────────────────────────────────────────
-- PART 2: Backfill existing deal_receipts rows
-- Fixes: receipt books (TP Receipts tab + member My Receipts)
--        for all records created before the RLS fix above.
-- ─────────────────────────────────────────────────────────────

-- Step 2a: Ensure member_email is populated (used as fallback for name).
UPDATE public.deal_receipts dr
SET    member_email = p.email,
       updated_at   = NOW()
FROM   public.profiles p
WHERE  p.id = dr.member_id
  AND  (dr.member_email IS NULL OR TRIM(dr.member_email) = '')
  AND  p.email IS NOT NULL
  AND  TRIM(p.email) <> '';

-- Step 2b: Backfill member_name from name + surname where it is blank or a placeholder.
UPDATE public.deal_receipts dr
SET    member_name = TRIM(COALESCE(p.name, '') || ' ' || COALESCE(p.surname, '')),
       updated_at  = NOW()
FROM   public.profiles p
WHERE  p.id = dr.member_id
  AND  TRIM(COALESCE(p.name, '') || ' ' || COALESCE(p.surname, '')) <> ''
  AND  (
         dr.member_name IS NULL
         OR TRIM(dr.member_name) = ''
         OR dr.member_name IN ('Unknown Member', 'Unknown user', 'Member', 'N/A', ' ')
       );

-- Step 2c: For profiles with no name/surname, fall back to email.
UPDATE public.deal_receipts dr
SET    member_name = COALESCE(NULLIF(TRIM(dr.member_email), ''), p.email),
       updated_at  = NOW()
FROM   public.profiles p
WHERE  p.id = dr.member_id
  AND  (
         dr.member_name IS NULL
         OR TRIM(dr.member_name) = ''
         OR dr.member_name IN ('Unknown Member', 'Unknown user', 'Member', 'N/A', ' ')
       )
  AND  COALESCE(NULLIF(TRIM(dr.member_email), ''), p.email) IS NOT NULL;

-- Step 2d: Backfill business_name where it is blank or a placeholder.
UPDATE public.deal_receipts dr
SET    business_name = b.name,
       updated_at    = NOW()
FROM   public.businesses b
WHERE  b.id = dr.business_id
  AND  b.name IS NOT NULL
  AND  TRIM(b.name) <> ''
  AND  (
         dr.business_name IS NULL
         OR TRIM(dr.business_name) = ''
         OR dr.business_name IN ('Business', 'Trusted Partner', 'N/A')
       );

-- ─────────────────────────────────────────────────────────────
-- PART 3: Backfill virtual_receipts.receipt_data JSON
-- Fixes: any member receipt detail views that read from
--        virtual_receipts.receipt_data->>'member_name'.
-- ─────────────────────────────────────────────────────────────

-- Step 3a: Patch member_name inside the receipt_data JSON blob.
UPDATE public.virtual_receipts vr
SET    receipt_data = jsonb_set(
                        vr.receipt_data,
                        '{member_name}',
                        to_jsonb(TRIM(COALESCE(p.name, '') || ' ' || COALESCE(p.surname, ''))),
                        true
                      )
FROM   public.deal_authorizations da
JOIN   public.profiles p ON p.id = da.member_id
WHERE  vr.deal_authorization_id = da.id
  AND  TRIM(COALESCE(p.name, '') || ' ' || COALESCE(p.surname, '')) <> ''
  AND  (
         vr.receipt_data->>'member_name' IS NULL
         OR TRIM(vr.receipt_data->>'member_name') = ''
         OR vr.receipt_data->>'member_name' IN ('Unknown Member', 'Unknown user', 'Member', 'N/A', ' ')
       );

-- Step 3b: Fall back to email for virtual_receipts where profile has no name.
UPDATE public.virtual_receipts vr
SET    receipt_data = jsonb_set(
                        vr.receipt_data,
                        '{member_name}',
                        to_jsonb(p.email),
                        true
                      )
FROM   public.deal_authorizations da
JOIN   public.profiles p ON p.id = da.member_id
WHERE  vr.deal_authorization_id = da.id
  AND  p.email IS NOT NULL
  AND  TRIM(p.email) <> ''
  AND  (
         vr.receipt_data->>'member_name' IS NULL
         OR TRIM(vr.receipt_data->>'member_name') = ''
         OR vr.receipt_data->>'member_name' IN ('Unknown Member', 'Unknown user', 'Member', 'N/A', ' ')
       );

COMMIT;

-- ─────────────────────────────────────────────────────────────
-- Verification queries (uncomment and run after the COMMIT)
-- ─────────────────────────────────────────────────────────────

-- Rows still showing a placeholder member name in deal_receipts:
-- SELECT id, receipt_number, member_id, member_name, member_email
-- FROM public.deal_receipts
-- WHERE member_name IS NULL
--    OR TRIM(member_name) = ''
--    OR member_name IN ('Unknown Member', 'Unknown user', 'Member', 'N/A');

-- Rows still showing a placeholder member name in virtual_receipts:
-- SELECT id, deal_authorization_id, receipt_data->>'member_name' AS member_name
-- FROM public.virtual_receipts
-- WHERE receipt_data->>'member_name' IS NULL
--    OR TRIM(receipt_data->>'member_name') = ''
--    OR receipt_data->>'member_name' IN ('Unknown Member', 'Unknown user', 'Member', 'N/A');

-- Confirm the RLS policy was created:
-- SELECT policyname, cmd, qual
-- FROM pg_policies
-- WHERE tablename = 'profiles'
--   AND policyname = 'TPs can read profiles of members with deal authorizations';
