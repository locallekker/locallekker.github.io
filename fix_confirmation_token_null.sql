-- Fix confirmation_token NULL issue for admin-created user
UPDATE auth.users
SET confirmation_token = ''
WHERE email = 'thecraftsmanel@gmail.com'
  AND confirmation_token IS NULL;

-- Verify
SELECT email, confirmation_token, confirmation_token IS NULL as is_null
FROM auth.users
WHERE email IN ('thecraftsmanel@gmail.com', 'clydemflan@gmail.com');
