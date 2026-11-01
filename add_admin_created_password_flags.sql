-- Add admin_created and password_set flags to profiles table
-- These flags track trusted partners created by admins who need to set their initial password

-- Add admin_created column (defaults to false for existing users)
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS admin_created BOOLEAN DEFAULT FALSE;

-- Add password_set column (defaults to true for existing users who already have passwords)
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS password_set BOOLEAN DEFAULT TRUE;

-- Add helpful comments
COMMENT ON COLUMN profiles.admin_created IS 'True if this account was created by an admin (not self-signup)';
COMMENT ON COLUMN profiles.password_set IS 'True if user has set their own password (false for admin-created accounts with temp passwords)';

-- Create index for efficient lookups of admin-created users
CREATE INDEX IF NOT EXISTS idx_profiles_admin_created ON profiles(admin_created) WHERE admin_created = TRUE;
CREATE INDEX IF NOT EXISTS idx_profiles_password_set ON profiles(password_set) WHERE password_set = FALSE;
