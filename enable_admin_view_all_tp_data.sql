-- Complete RLS policies to allow admin to view all trusted partner data
-- Run this SQL in Supabase to enable admin access to all TP information

-- 1. Allow admin to view all trusted partners (including unique_key)
DROP POLICY IF EXISTS "Admin can view all trusted partners" ON trusted_partners;
CREATE POLICY "Admin can view all trusted partners"
  ON trusted_partners
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 2. Allow admin to view all memberships (for status)
DROP POLICY IF EXISTS "Admin can view all memberships" ON memberships;
CREATE POLICY "Admin can view all memberships"
  ON memberships
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 3. Allow admin to view all QR codes (for QR status)
DROP POLICY IF EXISTS "Admin can view all user QR codes" ON user_qr_codes;
CREATE POLICY "Admin can view all user QR codes"
  ON user_qr_codes
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 4. Allow admin to view all deals (already applied)
DROP POLICY IF EXISTS "Admin can view all trusted partner discounts" ON trusted_partner_discounts;
CREATE POLICY "Admin can view all trusted partner discounts"
  ON trusted_partner_discounts
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 5. Allow admin to view all businesses table data
DROP POLICY IF EXISTS "Admin can view all businesses" ON businesses;
CREATE POLICY "Admin can view all businesses"
  ON businesses
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Verify all policies were created
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE policyname LIKE '%Admin can view%'
ORDER BY tablename;
