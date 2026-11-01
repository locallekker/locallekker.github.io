-- Create Admin User for Local Lekker
-- Email: locallekkerclub@gmail.com
-- Password: 123456
-- This script creates an admin user with full access to the admin dashboard

-- Note: This script should be run in the Supabase SQL Editor
-- The user will need to confirm their email unless you disable email confirmation

-- Step 1: Create the auth user (you may need to do this via Supabase Dashboard Auth section)
-- Or use the admin API, but for SQL we'll create the profile and membership records
-- assuming the auth user already exists

-- If you want to create the auth user via SQL (requires admin privileges):
-- You'll need to get the user_id after creating via Supabase Dashboard Authentication section

-- For this script, we'll assume you create the user via Supabase Dashboard first:
-- 1. Go to Authentication > Users
-- 2. Click "Add User"
-- 3. Email: locallekkerclub@gmail.com
-- 4. Password: 123456
-- 5. Email Confirm: Yes (or No if you want to skip verification)
-- 6. Copy the User ID that gets generated

-- Then run this script, replacing 'YOUR_USER_ID_HERE' with the actual UUID

-- ============================================
-- ADMIN USER ID: 985fa2aa-45c7-450a-a8b8-ff63934a6193
-- ============================================
DO $$
DECLARE
  admin_user_id uuid := '985fa2aa-45c7-450a-a8b8-ff63934a6193'::uuid;
BEGIN
  -- Create profile for admin user
  INSERT INTO public.profiles (
    id,
    email,
    name,
    surname,
    role,
    created_at,
    updated_at
  ) VALUES (
    admin_user_id,
    'locallekkerclub@gmail.com',
    'Local Lekker',
    'Admin',
    'admin',
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    name = EXCLUDED.name,
    surname = EXCLUDED.surname,
    role = EXCLUDED.role,
    updated_at = now();

  -- Create membership record with admin role
  INSERT INTO public.memberships (
    user_id,
    role,
    gateway,
    created_at,
    updated_at
  ) VALUES (
    admin_user_id,
    'admin',
    'manual',
    now(),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    role = 'admin',
    updated_at = now();

  RAISE NOTICE 'Admin user setup completed for: locallekkerclub@gmail.com';
END $$;

-- ============================================
-- ALTERNATIVE: Complete script if you have admin API access
-- ============================================
-- If you can't create the user via dashboard, you can use this approach:
-- This requires running from a context with admin privileges

/*
-- Use Supabase Admin API or run this with service role key
SELECT extensions.create_user(
  email => 'locallekkerclub@gmail.com',
  password => '123456',
  email_confirm => true
);

-- Then get the user_id and run the profile creation above
*/

-- ============================================
-- VERIFICATION QUERIES
-- ============================================
-- After running, verify the admin user was created:

-- Check if profile exists
SELECT id, email, name, surname, role 
FROM public.profiles 
WHERE email = 'locallekkerclub@gmail.com';

-- Check membership
SELECT user_id, role, gateway 
FROM public.memberships 
WHERE user_id IN (
  SELECT id FROM public.profiles WHERE email = 'locallekkerclub@gmail.com'
);
