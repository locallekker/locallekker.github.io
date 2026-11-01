-- ============================================================
-- FIX v2: Infinite recursion in profiles RLS policy
-- 
-- ROOT CAUSE: Cross-table RLS cycle:
--   profiles → trusted_partners (tp_can_read_member_profiles)
--   trusted_partners → profiles ("Admin can view all trusted partners")
-- 
-- Fix: Use ONLY JWT metadata checks (zero subqueries).
-- JWT claims are evaluated in-memory, never trigger RLS on any table.
-- ============================================================

-- 1. Drop the problematic policy
DROP POLICY IF EXISTS tp_can_read_member_profiles ON profiles;

-- 2. Re-create using ONLY JWT metadata (zero subqueries = zero recursion risk)
CREATE POLICY tp_can_read_member_profiles ON profiles
  FOR SELECT
  TO authenticated
  USING (
    role = 'member'
    AND (auth.jwt() -> 'user_metadata' ->> 'user_type') = 'trusted_partner'
  );

-- 3. Also fix user_qr_codes policy to use JWT-only pattern
DROP POLICY IF EXISTS tp_can_read_user_qr_codes ON user_qr_codes;

CREATE POLICY tp_can_read_user_qr_codes ON user_qr_codes
  FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() -> 'user_metadata' ->> 'user_type') = 'trusted_partner'
  );

-- 4. BONUS: Fix the trusted_partners admin policy that was the other half of the cycle
-- Replace: SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
-- With: JWT-based admin check
DROP POLICY IF EXISTS "Admin can view all trusted partners" ON trusted_partners;

CREATE POLICY "Admin can view all trusted partners" ON trusted_partners
  FOR SELECT
  TO authenticated
  USING (
    -- Use memberships table (safe, no cycle) OR JWT email check
    EXISTS (
      SELECT 1 FROM memberships
      WHERE user_id = auth.uid() AND role = 'admin'
    )
    OR auth.jwt() ->> 'email' IN ('admin@locallekker.com', 'locallekkerclub@gmail.com', 'clydemflan@gmail.com')
  );

-- Verify all three policies
SELECT tablename, policyname, cmd, qual 
FROM pg_policies 
WHERE policyname IN (
  'tp_can_read_member_profiles', 
  'tp_can_read_user_qr_codes',
  'Admin can view all trusted partners'
)
ORDER BY tablename;
