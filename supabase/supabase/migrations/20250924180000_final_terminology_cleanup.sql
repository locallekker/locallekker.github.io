-- Migration: Ensure all merchant-related tables are properCREATE POLICY "Members can view their own discounts" ON public.trusted_partner_discounts
  FOR SELECT USING ((SELECT auth.uid()) = trusted_partner_id);

CREATE POLICY "Members can insert their own discounts" ON public.trusted_partner_discounts
  FOR INSERT WITH CHECK ((SELECT auth.uid()) = trusted_partner_id);

CREATE POLICY "Members can update their own discounts" ON public.trusted_partner_discounts
  FOR UPDATE USING ((SELECT auth.uid()) = trusted_partner_id);

CREATE POLICY "Members can delete their own discounts" ON public.trusted_partner_discounts
  FOR DELETE USING ((SELECT auth.uid()) = trusted_partner_id);to trusted_partner terminology
-- This migration handles any remaining references and ensures consistency

BEGIN;

-- Step 1: Rename merchants table to trusted_partners if it still exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'merchants') THEN
    ALTER TABLE public.merchants RENAME TO trusted_partners;
  END IF;
END $$;

-- Step 2: Rename merchant_discounts table to trusted_partner_discounts if it still exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'merchant_discounts') THEN
    ALTER TABLE public.merchant_discounts RENAME TO trusted_partner_discounts;
  END IF;
END $$;

-- Step 3: Rename merchant_id column to trusted_partner_id in trusted_partner_discounts if it still exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'trusted_partner_discounts' AND column_name = 'merchant_id') THEN
    ALTER TABLE public.trusted_partner_discounts RENAME COLUMN merchant_id TO trusted_partner_id;
  END IF;
END $$;

-- Step 4: Update any remaining role values from 'merchant' to 'trusted_partner'
UPDATE public.profiles
SET role = 'trusted_partner'
WHERE role = 'merchant';

UPDATE public.memberships
SET role = 'trusted_partner'
WHERE role = 'merchant';

-- Step 5: Ensure foreign key constraints are correct
ALTER TABLE public.trusted_partner_discounts DROP CONSTRAINT IF EXISTS merchant_discounts_merchant_id_fkey;
ALTER TABLE public.trusted_partner_discounts DROP CONSTRAINT IF EXISTS trusted_partner_discounts_merchant_id_fkey;
ALTER TABLE public.trusted_partner_discounts DROP CONSTRAINT IF EXISTS trusted_partner_discounts_trusted_partner_id_fkey;

ALTER TABLE public.trusted_partner_discounts
ADD CONSTRAINT trusted_partner_discounts_trusted_partner_id_fkey
FOREIGN KEY (trusted_partner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Step 6: Update RLS policies to use correct terminology
DROP POLICY IF EXISTS "Users can view their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can insert their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can update their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can delete their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can view active discounts from all merchants" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Members can view their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Members can insert their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Members can update their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Members can delete their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Members can view active discounts from all trusted partners" ON public.trusted_partner_discounts;

CREATE POLICY "Members can view their own discounts" ON public.trusted_partner_discounts
  FOR SELECT USING (auth.uid() = trusted_partner_id);

CREATE POLICY "Members can insert their own discounts" ON public.trusted_partner_discounts
  FOR INSERT WITH CHECK (auth.uid() = trusted_partner_id);

CREATE POLICY "Members can update their own discounts" ON public.trusted_partner_discounts
  FOR UPDATE USING (auth.uid() = trusted_partner_id);

CREATE POLICY "Members can delete their own discounts" ON public.trusted_partner_discounts
  FOR DELETE USING (auth.uid() = trusted_partner_id);

CREATE POLICY "Members can view active discounts from all trusted partners" ON public.trusted_partner_discounts
  FOR SELECT USING (is_active = true);

-- Step 7: Update indexes
DROP INDEX IF EXISTS idx_merchant_discounts_merchant_id;
DROP INDEX IF EXISTS idx_merchant_discounts_active;
DROP INDEX IF EXISTS idx_trusted_partner_discounts_merchant_id;

CREATE INDEX IF NOT EXISTS idx_trusted_partner_discounts_trusted_partner_id ON public.trusted_partner_discounts(trusted_partner_id);
CREATE INDEX IF NOT EXISTS idx_trusted_partner_discounts_active ON public.trusted_partner_discounts(is_active);

COMMIT;</content>
<parameter name="filePath">c:\Users\clyde\local_lekker\supabase\migrations\20250924180000_final_terminology_cleanup.sql