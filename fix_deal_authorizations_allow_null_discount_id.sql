-- Fix: Allow deleting a deal (trusted_partner_discounts row) without
-- violating deal_authorizations.discount_id NOT NULL constraint.
--
-- Problem:
--   deal_authorizations.discount_id is defined as NOT NULL, but its
--   foreign key uses ON DELETE SET NULL. When an admin or trusted partner
--   tries to delete a deal, Postgres attempts to set discount_id = NULL on
--   referencing rows and fails with:
--     "null value in column 'discount_id' of relation
--      'deal_authorizations' violates not-null constraint" (code 23502)
--
-- Resolution:
--   Drop NOT NULL on deal_authorizations.discount_id (and processed_bills
--   for the same reason), and ensure the FK is ON DELETE SET NULL so
--   historical authorization/bill records are preserved when the parent
--   deal is removed.

BEGIN;

-- 1) deal_authorizations.discount_id: allow NULL
ALTER TABLE public.deal_authorizations
  ALTER COLUMN discount_id DROP NOT NULL;

-- Re-assert FK with ON DELETE SET NULL (idempotent)
ALTER TABLE public.deal_authorizations
  DROP CONSTRAINT IF EXISTS deal_authorizations_discount_id_fkey;

ALTER TABLE public.deal_authorizations
  ADD CONSTRAINT deal_authorizations_discount_id_fkey
  FOREIGN KEY (discount_id)
  REFERENCES public.trusted_partner_discounts(id)
  ON DELETE SET NULL;

-- 2) processed_bills.discount_id: allow NULL (same root cause)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'processed_bills'
      AND column_name = 'discount_id'
  ) THEN
    EXECUTE 'ALTER TABLE public.processed_bills ALTER COLUMN discount_id DROP NOT NULL';

    EXECUTE 'ALTER TABLE public.processed_bills DROP CONSTRAINT IF EXISTS processed_bills_discount_id_fkey';

    EXECUTE 'ALTER TABLE public.processed_bills
             ADD CONSTRAINT processed_bills_discount_id_fkey
             FOREIGN KEY (discount_id)
             REFERENCES public.trusted_partner_discounts(id)
             ON DELETE SET NULL';
  END IF;
END$$;

COMMIT;

-- Verification:
-- SELECT column_name, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema='public'
--   AND table_name IN ('deal_authorizations','processed_bills')
--   AND column_name='discount_id';
