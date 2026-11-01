-- Create admin user manually in Supabase Dashboard
-- This migration provides instructions since auth.admin.create_user() is not accessible from SQL editor

-- MANUAL STEPS REQUIRED:
-- 1. Go to Supabase Dashboard > Authentication > Users
-- 2. Click "Add user"
-- 3. Enter:
--    Email: admin@locallekker.com
--    Password: Admin123!
--    Auto-confirm user: CHECKED
--    User metadata: {"name": "Admin", "surname": "User"}
-- 4. Click "Create user"
-- 5. Copy the User ID from the created user
-- 6. Run the SQL below in Supabase Dashboard > SQL Editor, replacing 'YOUR_ADMIN_USER_ID_HERE' with the actual UUID

-- SQL to run after creating user in dashboard:
/*
-- Replace YOUR_ADMIN_USER_ID_HERE with the actual user ID from the dashboard
DO $$
DECLARE
  admin_user_id UUID := 'YOUR_ADMIN_USER_ID_HERE';
BEGIN
  -- Insert into profiles
  INSERT INTO public.profiles (
    id,
    name,
    surname,
    email,
    category,
    role,
    created_at,
    updated_at
  ) VALUES (
    admin_user_id,
    'Admin',
    'User',
    'admin@locallekker.com',
    'admin',
    'admin',
    NOW(),
    NOW()
  ) ON CONFLICT (id) DO NOTHING;

  -- Insert into memberships
  INSERT INTO public.memberships (
    user_id,
    role,
    status,
    created_at,
    updated_at
  ) VALUES (
    admin_user_id,
    'admin',
    'active',
    NOW(),
    NOW()
  ) ON CONFLICT (user_id) DO NOTHING;

END $$;
*/