-- =====================================================
-- Trusted Partner OTP Flow Migration
-- =====================================================
-- This script updates the database to support the new
-- trusted partner authentication flow without temp passwords
-- =====================================================

-- 1. Add email_verified column to profiles table
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS email_verified BOOLEAN DEFAULT true;

-- 2. Add password_set column to profiles table  
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS password_set BOOLEAN DEFAULT true;

-- 3. Add admin_created column if it doesn't exist
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS admin_created BOOLEAN DEFAULT false;

-- 4. Update existing admin-created users to have correct status
-- Set email_verified and password_set to false for unverified admin-created users
UPDATE profiles 
SET email_verified = false,
    password_set = false
WHERE admin_created = true 
  AND id IN (
    SELECT au.id 
    FROM auth.users au 
    WHERE au.raw_user_meta_data->>'admin_created' = 'true' 
      AND au.raw_user_meta_data->>'email_verified' = 'false'
      AND au.email_confirmed_at IS NULL
  );

-- 5. Create indexes for faster lookups
CREATE INDEX IF NOT EXISTS idx_profiles_email_verified 
ON profiles(email, email_verified);

CREATE INDEX IF NOT EXISTS idx_profiles_password_set 
ON profiles(password_set);

CREATE INDEX IF NOT EXISTS idx_profiles_admin_created 
ON profiles(admin_created);

-- 6. Verify the migration
-- This query should show all admin-created trusted partners with their status
SELECT 
    p.id,
    p.email,
    p.name,
    p.surname,
    p.admin_created,
    p.email_verified,
    p.password_set,
    p.created_at,
    tp.business_name,
    m.role,
    au.email_confirmed_at
FROM profiles p
LEFT JOIN trusted_partners tp ON p.id = tp.user_id
LEFT JOIN memberships m ON p.id = m.user_id
LEFT JOIN auth.users au ON p.id = au.id
WHERE p.admin_created = true
ORDER BY p.created_at DESC;

-- 7. Count trusted partners by status
SELECT 
    admin_created,
    email_verified,
    password_set,
    COUNT(*) as count
FROM profiles
WHERE admin_created = true
GROUP BY admin_created, email_verified, password_set;
