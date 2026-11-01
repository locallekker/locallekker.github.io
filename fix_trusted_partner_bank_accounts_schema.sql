-- ========================================
-- FIX TRUSTED PARTNER BANK ACCOUNTS SCHEMA
-- Change from business_id to user_id (trusted_partner_id)
-- ========================================

-- Step 1: Add new user_id column to trusted_partner_bank_accounts
ALTER TABLE public.trusted_partner_bank_accounts
ADD COLUMN IF NOT EXISTS user_id uuid;

-- Step 2: Migrate existing data from business_id to user_id
-- This maps business owners to their bank accounts
UPDATE public.trusted_partner_bank_accounts tpba
SET user_id = b.owner_member_id
FROM public.businesses b
WHERE tpba.business_id = b.id
  AND tpba.user_id IS NULL;

-- Step 3: Drop the old foreign key constraint on business_id
ALTER TABLE public.trusted_partner_bank_accounts
DROP CONSTRAINT IF EXISTS trusted_partner_bank_accounts_business_id_fkey;

-- Step 4: Make user_id NOT NULL (after data migration)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.trusted_partner_bank_accounts WHERE user_id IS NULL
    ) THEN
        ALTER TABLE public.trusted_partner_bank_accounts
        ALTER COLUMN user_id SET NOT NULL;
    ELSE
        RAISE NOTICE 'Skipping SET NOT NULL on user_id because NULL values still exist. Please resolve and rerun.';
    END IF;
END $$;

-- Step 5: Add new foreign key constraint on user_id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON c.conrelid = t.oid
        WHERE t.relname = 'trusted_partner_bank_accounts'
            AND c.conname = 'trusted_partner_bank_accounts_user_id_fkey'
    ) THEN
        ALTER TABLE public.trusted_partner_bank_accounts
        ADD CONSTRAINT trusted_partner_bank_accounts_user_id_fkey 
        FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
    END IF;
END $$;

-- Step 6: Keep business_id as optional reference (for backward compatibility)
-- Or drop it entirely if not needed
-- Option A: Keep it as optional reference
-- (Do nothing, business_id stays as nullable column)

-- Option B: Drop business_id entirely (RECOMMENDED for clean schema)
-- Uncomment the following line if you want to remove business_id:
-- ALTER TABLE public.trusted_partner_bank_accounts DROP COLUMN business_id;

-- Step 7: Create index on user_id for performance
CREATE INDEX IF NOT EXISTS idx_trusted_partner_bank_accounts_user_id 
ON public.trusted_partner_bank_accounts(user_id);

-- Step 8: Verify the migration
SELECT 
    tpba.id,
    tpba.user_id,
    tpba.business_id,
    tpba.account_holder_name,
    tpba.bank_name,
    p.name AS user_name,
    p.surname AS user_surname
FROM 
    public.trusted_partner_bank_accounts tpba
    JOIN public.profiles p ON tpba.user_id = p.id
LIMIT 10;

-- Step 9: Check for any orphaned records (bank accounts without valid user_id)
SELECT 
    tpba.id,
    tpba.business_id,
    tpba.account_holder_name,
    tpba.bank_name
FROM 
    public.trusted_partner_bank_accounts tpba
    LEFT JOIN public.profiles p ON tpba.user_id = p.id
WHERE 
    p.id IS NULL;
