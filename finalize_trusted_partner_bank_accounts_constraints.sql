-- ========================================
-- FINALIZE CONSTRAINTS FOR TRUSTED_PARTNER_BANK_ACCOUNTS
-- Ensure unique constraint on (user_id, account_number, branch_code)
-- and remove any legacy business_id-based unique constraints/indexes
-- Idempotent and safe to re-run
-- ========================================

-- 1) Create a unique index on (user_id, account_number, branch_code) if not exists
-- Note: A UNIQUE INDEX provides the same guarantees as a named UNIQUE CONSTRAINT
CREATE UNIQUE INDEX IF NOT EXISTS idx_tpba_user_acc_branch_unique
ON public.trusted_partner_bank_accounts(user_id, account_number, branch_code);

-- 2) Drop legacy unique constraints that include business_id
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT conname
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'public'
          AND t.relname = 'trusted_partner_bank_accounts'
          AND c.contype = 'u'  -- unique
          AND EXISTS (
                SELECT 1
                FROM unnest(c.conkey) AS col_attnum
                JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = col_attnum
                WHERE a.attname = 'business_id'
          )
    LOOP
        EXECUTE format('ALTER TABLE public.trusted_partner_bank_accounts DROP CONSTRAINT IF EXISTS %I;', r.conname);
    END LOOP;
END $$;

-- 3) Drop any legacy index on business_id (if created previously)
DROP INDEX IF EXISTS public.idx_trusted_partner_bank_accounts_business_id;

-- 4) Quick verification (optional)
-- List unique indexes/constraints now present
SELECT
    i.relname AS index_name,
    idx.indisunique AS is_unique,
    array_agg(a.attname ORDER BY a.attnum) AS columns
FROM pg_index idx
JOIN pg_class i ON i.oid = idx.indexrelid
JOIN pg_class t ON t.oid = idx.indrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
LEFT JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(idx.indkey)
WHERE n.nspname = 'public'
  AND t.relname = 'trusted_partner_bank_accounts'
GROUP BY i.relname, idx.indisunique
ORDER BY is_unique DESC, index_name;
