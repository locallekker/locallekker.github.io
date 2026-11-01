-- =====================================================
-- ADD VERIFIED STATUS TO PROFILES
-- For admin to distinguish pending vs verified users
-- =====================================================

-- Add verified column if it doesn't exist
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS verified BOOLEAN DEFAULT false;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_profiles_verified ON profiles(verified);
CREATE INDEX IF NOT EXISTS idx_profiles_role_verified ON profiles(role, verified);

-- Update existing users to verified (assuming current users are already verified)
UPDATE profiles 
SET verified = true 
WHERE verified IS NULL OR verified = false;

-- Optional: Set admin-created TPs as pending until admin verifies them
UPDATE profiles 
SET verified = false 
WHERE role = 'trusted_partner' 
  AND admin_created = true 
  AND password_set = false;

COMMENT ON COLUMN profiles.verified IS 'Admin verification status: false = pending, true = verified';
