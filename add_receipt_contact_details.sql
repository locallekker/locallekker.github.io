-- Add denormalized contact details to deal_receipts.
--
-- Why: receipts must display the counterparty's contact info.
--   * Member's receipt  -> trusted partner business name + contact number + email
--   * Trusted partner's receipt -> member name/surname + contact number + email
-- The member name (name+surname) and member_email already exist. This adds:
--   * business_contact  (businesses.contact_number)
--   * business_email    (businesses.contact_email)
--   * member_phone      (profiles.contact)
--
-- Safety: additive columns only; backfill is idempotent (only fills blanks).

BEGIN;

ALTER TABLE public.deal_receipts
  ADD COLUMN IF NOT EXISTS business_contact TEXT,
  ADD COLUMN IF NOT EXISTS business_email   TEXT,
  ADD COLUMN IF NOT EXISTS member_phone     TEXT;

COMMENT ON COLUMN public.deal_receipts.business_contact IS 'Trusted partner business contact number (denormalized from businesses.contact_number)';
COMMENT ON COLUMN public.deal_receipts.business_email   IS 'Trusted partner business email (denormalized from businesses.contact_email)';
COMMENT ON COLUMN public.deal_receipts.member_phone     IS 'Member contact number (denormalized from profiles.contact)';

-- Backfill business contact/email from the businesses table where missing.
UPDATE public.deal_receipts dr
SET    business_contact = b.contact_number,
       business_email   = b.contact_email,
       updated_at       = NOW()
FROM   public.businesses b
WHERE  b.id = dr.business_id
  AND  (
         (dr.business_contact IS NULL AND b.contact_number IS NOT NULL)
         OR (dr.business_email IS NULL AND b.contact_email IS NOT NULL)
       );

-- Backfill member phone from profiles where missing.
UPDATE public.deal_receipts dr
SET    member_phone = p.contact,
       updated_at   = NOW()
FROM   public.profiles p
WHERE  p.id = dr.member_id
  AND  dr.member_phone IS NULL
  AND  p.contact IS NOT NULL
  AND  TRIM(p.contact) <> '';

COMMIT;
