-- ============================================================================
-- DEACTIVATION FEATURE DATABASE MIGRATION
-- Date: 2026-01-09
-- Purpose: Add support for account deactivation for members and trusted partners
-- ============================================================================

-- =============================================================================
-- 1. ADD DEACTIVATION COLUMNS TO PROFILES TABLE
-- =============================================================================
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_deactivated BOOLEAN DEFAULT FALSE;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS deactivation_reason TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS deactivated_at TIMESTAMP WITH TIME ZONE;

-- =============================================================================
-- 2. ADD DEACTIVATION FLAG TO TRUSTED_PARTNERS TABLE (OPTIONAL OPTIMIZATION)
-- =============================================================================
ALTER TABLE trusted_partners ADD COLUMN IF NOT EXISTS is_deactivated BOOLEAN DEFAULT FALSE;

-- =============================================================================
-- 3. CREATE INDEXES FOR PERFORMANCE
-- =============================================================================
-- Index for faster deactivation queries by role and status
CREATE INDEX IF NOT EXISTS idx_profiles_is_deactivated 
ON profiles(is_deactivated, role);

-- Index for ordering deactivated accounts by timestamp
CREATE INDEX IF NOT EXISTS idx_profiles_deactivated_at 
ON profiles(deactivated_at) 
WHERE is_deactivated = TRUE;

-- Index for trusted_partners deactivation queries
CREATE INDEX IF NOT EXISTS idx_trusted_partners_is_deactivated 
ON trusted_partners(is_deactivated);

-- Index for subscription deactivation queries
CREATE INDEX IF NOT EXISTS idx_subscriptions_status_deactivated 
ON subscriptions(user_id, status) 
WHERE status = 'deactivated';

-- =============================================================================
-- 4. UPDATE RLS POLICIES TO RESPECT DEACTIVATION STATUS
-- =============================================================================

-- Drop existing policies if they exist (prevents conflicts)
DROP POLICY IF EXISTS "Members can view all active trusted partners" ON profiles;
DROP POLICY IF EXISTS "Members cannot see deactivated profiles" ON profiles;

-- Create new policy: Members can view active trusted partners
CREATE POLICY "Members can view active trusted partners" ON profiles
    FOR SELECT USING (
        (role = 'trusted_partner' AND is_deactivated = FALSE)
        OR id = auth.uid()  -- Can always see own profile
    );

-- Create policy: Prevent viewing deactivated other profiles
CREATE POLICY "Members cannot see deactivated profiles" ON profiles
    FOR SELECT USING (
        is_deactivated = FALSE OR id = auth.uid()
    );

-- Update trusted partner deals visibility policy
DROP POLICY IF EXISTS "Members can view active deals from non-deactivated partners" ON trusted_partner_discounts;

CREATE POLICY "Members can view active deals from non-deactivated partners" ON trusted_partner_discounts
    FOR SELECT USING (
        is_active = TRUE
        AND trusted_partner_id NOT IN (
            SELECT id FROM profiles 
            WHERE is_deactivated = TRUE AND role = 'trusted_partner'
        )
    );

-- =============================================================================
-- 5. VERIFICATION QUERIES - RUN THESE TO VERIFY SETUP
-- =============================================================================

-- Verify columns were created
-- SELECT 
--     column_name, 
--     data_type, 
--     is_nullable
-- FROM information_schema.columns
-- WHERE table_name = 'profiles' 
-- AND column_name IN ('is_deactivated', 'deactivation_reason', 'deactivated_at');

-- Verify indexes were created
-- SELECT indexname, indexdef 
-- FROM pg_indexes 
-- WHERE tablename = 'profiles'
-- AND indexname LIKE '%deactivat%';

-- Count current deactivated accounts
-- SELECT role, COUNT(*) as deactivated_count
-- FROM profiles
-- WHERE is_deactivated = TRUE
-- GROUP BY role;

-- =============================================================================
-- 6. OPTIONAL: DATA MIGRATION FOR EXISTING DEACTIVATED ACCOUNTS
-- =============================================================================
-- If you have existing deactivated accounts (from manual updates),
-- uncomment and run these to initialize the new fields:

-- Initialize deactivation timestamps for existing records
-- UPDATE profiles 
-- SET deactivated_at = NOW()
-- WHERE is_deactivated = TRUE AND deactivated_at IS NULL;

-- Set default reason for existing deactivations
-- UPDATE profiles 
-- SET deactivation_reason = 'User requested deactivation'
-- WHERE is_deactivated = TRUE AND deactivation_reason IS NULL;

-- =============================================================================
-- MIGRATION COMPLETE
-- The deactivation feature is now ready to use
-- =============================================================================
