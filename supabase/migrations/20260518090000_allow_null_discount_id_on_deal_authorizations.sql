-- Allow deleting trusted_partner_discounts without violating NOT NULL on
-- deal_authorizations.discount_id (and processed_bills.discount_id).
-- See: fix_deal_authorizations_allow_null_discount_id.sql

BEGIN;

ALTER TABLE public.deal_authorizations
  ALTER COLUMN discount_id DROP NOT NULL;

ALTER TABLE public.deal_authorizations
  DROP CONSTRAINT IF EXISTS deal_authorizations_discount_id_fkey;

ALTER TABLE public.deal_authorizations
  ADD CONSTRAINT deal_authorizations_discount_id_fkey
  FOREIGN KEY (discount_id)
  REFERENCES public.trusted_partner_discounts(id)
  ON DELETE SET NULL;

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
