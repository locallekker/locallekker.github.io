-- Migration: Rename merchant_discounts table to trusted_partner_discounts
-- This completes the terminology update for discount-related tables

BEGIN;

-- Step 1: Rename the table
ALTER TABLE IF EXISTS public.merchant_discounts RENAME TO trusted_partner_discounts;

-- Step 2: Rename the column
ALTER TABLE IF EXISTS public.trusted_partner_discounts RENAME COLUMN merchant_id TO trusted_partner_id;

-- Step 3: Update foreign key constraint
ALTER TABLE IF EXISTS public.trusted_partner_discounts DROP CONSTRAINT IF EXISTS merchant_discounts_merchant_id_fkey;
ALTER TABLE public.trusted_partner_discounts
ADD CONSTRAINT trusted_partner_discounts_trusted_partner_id_fkey
FOREIGN KEY (trusted_partner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Step 4: Drop old policies
DROP POLICY IF EXISTS "Users can view their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can insert their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can update their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can delete their own discounts" ON public.trusted_partner_discounts;
DROP POLICY IF EXISTS "Users can view active discounts from all merchants" ON public.trusted_partner_discounts;

-- Step 5: Create new policies with updated terminology
CREATE POLICY "Members can view their own discounts" ON public.trusted_partner_discounts
  FOR SELECT USING ((SELECT auth.uid()) = trusted_partner_id);

CREATE POLICY "Members can insert their own discounts" ON public.trusted_partner_discounts
  FOR INSERT WITH CHECK ((SELECT auth.uid()) = trusted_partner_id);

CREATE POLICY "Members can update their own discounts" ON public.trusted_partner_discounts
  FOR UPDATE USING ((SELECT auth.uid()) = trusted_partner_id);

CREATE POLICY "Members can delete their own discounts" ON public.trusted_partner_discounts
  FOR DELETE USING ((SELECT auth.uid()) = trusted_partner_id);

CREATE POLICY "Members can view active discounts from all trusted partners" ON public.trusted_partner_discounts
  FOR SELECT USING (is_active = true);

-- Step 6: Drop old indexes
DROP INDEX IF EXISTS idx_merchant_discounts_merchant_id;
DROP INDEX IF EXISTS idx_merchant_discounts_active;

-- Step 7: Create new indexes with updated names
CREATE INDEX IF NOT EXISTS idx_trusted_partner_discounts_trusted_partner_id ON public.trusted_partner_discounts(trusted_partner_id);
CREATE INDEX IF NOT EXISTS idx_trusted_partner_discounts_active ON public.trusted_partner_discounts(is_active);

-- Step 8: Update the trigger function name and references
CREATE OR REPLACE FUNCTION update_trusted_partner_discounts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 9: Drop old trigger
DROP TRIGGER IF EXISTS update_merchant_discounts_updated_at_trigger ON public.trusted_partner_discounts;

-- Step 10: Create new trigger with updated name
CREATE TRIGGER update_trusted_partner_discounts_updated_at_trigger
  BEFORE UPDATE ON public.trusted_partner_discounts
  FOR EACH ROW
  EXECUTE FUNCTION update_trusted_partner_discounts_updated_at();

-- Step 11: Drop old function
DROP FUNCTION IF EXISTS update_merchant_discounts_updated_at();

COMMIT;</content>
<parameter name="filePath">c:\Users\clyde\local_lekker\supabase\migrations\20250924170000_rename_merchant_discounts_to_trusted_partner_discounts.sql