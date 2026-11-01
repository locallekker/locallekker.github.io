-- Test if admin-created user can sign in with bcrypt password
-- This tests password validation for thecraftsmanel@gmail.com

-- First, check the encrypted_password format
SELECT 
  email,
  LEFT(encrypted_password, 7) as bcrypt_prefix,  -- Should be '$2a$' or '$2b$' for bcrypt
  LENGTH(encrypted_password) as password_length  -- Should be 60 for bcrypt
FROM auth.users 
WHERE email IN ('thecraftsmanel@gmail.com', 'clydemflan@gmail.com')
ORDER BY email;

-- Check if both users have same encryption method
SELECT 
  email,
  encrypted_password LIKE '$2%' as is_bcrypt,
  raw_user_meta_data->>'admin_created' as admin_created
FROM auth.users 
WHERE email IN ('thecraftsmanel@gmail.com', 'clydemflan@gmail.com')
ORDER BY email;
