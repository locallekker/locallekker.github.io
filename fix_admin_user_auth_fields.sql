-- Fix existing admin-created user to enable password reset
UPDATE auth.users
SET 
  aud = 'authenticated',
  role = 'authenticated',
  instance_id = '00000000-0000-0000-0000-000000000000',
  raw_app_meta_data = '{"provider":"email","providers":["email"]}'::jsonb
WHERE email = 'thecraftsmanel@gmail.com';

-- Verify the fix
SELECT 
  email,
  aud,
  role,
  instance_id,
  raw_app_meta_data,
  email_confirmed_at IS NOT NULL as has_email_confirmed,
  confirmation_sent_at IS NOT NULL as has_confirmation_sent
FROM auth.users
WHERE email = 'thecraftsmanel@gmail.com';
