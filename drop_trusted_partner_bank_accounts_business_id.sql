-- ========================================
-- DROP business_id FROM TRUSTED_PARTNER_BANK_ACCOUNTS (Optional Cleanup)
-- Safely remove legacy column after migrating to user_id
-- Idempotent and safe to re-run
-- ========================================

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'trusted_partner_bank_accounts'
          AND column_name = 'business_id'
    ) THEN
        -- Ensure no remaining constraints reference business_id
        -- (Should be none after finalize_trusted_partner_bank_accounts_constraints.sql)
        -- Drop the column
        ALTER TABLE public.trusted_partner_bank_accounts
        DROP COLUMN business_id;
        RAISE NOTICE 'Dropped column business_id from public.trusted_partner_bank_accounts.';
    ELSE
        RAISE NOTICE 'Column business_id does not exist; nothing to drop.';
    END IF;
END $$;
