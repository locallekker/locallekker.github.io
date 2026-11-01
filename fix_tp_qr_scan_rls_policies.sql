-- ============================================================
-- RLS policies for Trusted Partner QR scanning
-- Allows authenticated trusted partners to read member profiles
-- and user_qr_codes for verification when scanning QR codes
-- ============================================================

-- 1. Allow trusted partners to read basic member profile info
-- (only members, limited fields enforced at app level)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE policyname = 'tp_can_read_member_profiles' 
    AND tablename = 'profiles'
  ) THEN
    CREATE POLICY tp_can_read_member_profiles ON profiles
      FOR SELECT
      TO authenticated
      USING (
        role = 'member'
        AND EXISTS (
          SELECT 1 FROM profiles tp
          WHERE tp.id = auth.uid()
          AND tp.role = 'trusted_partner'
        )
      );
    RAISE NOTICE 'Created policy: tp_can_read_member_profiles';
  ELSE
    RAISE NOTICE 'Policy tp_can_read_member_profiles already exists';
  END IF;
END $$;

-- 2. Allow trusted partners to read user_qr_codes for validation
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE policyname = 'tp_can_read_user_qr_codes' 
    AND tablename = 'user_qr_codes'
  ) THEN
    CREATE POLICY tp_can_read_user_qr_codes ON user_qr_codes
      FOR SELECT
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM profiles tp
          WHERE tp.id = auth.uid()
          AND tp.role = 'trusted_partner'
        )
      );
    RAISE NOTICE 'Created policy: tp_can_read_user_qr_codes';
  ELSE
    RAISE NOTICE 'Policy tp_can_read_user_qr_codes already exists';
  END IF;
END $$;

-- Verify policies exist
SELECT tablename, policyname, cmd 
FROM pg_policies 
WHERE policyname IN ('tp_can_read_member_profiles', 'tp_can_read_user_qr_codes')
ORDER BY tablename;
