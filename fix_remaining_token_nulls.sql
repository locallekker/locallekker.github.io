-- Fix remaining NULL token fields for admin-created user
-- Supabase auth service expects empty strings, not NULL

UPDATE auth.users 
SET 
  recovery_token = '',
  email_change_token_new = ''
WHERE email = 'thecraftsmanel@gmail.com' 
  AND (recovery_token IS NULL OR email_change_token_new IS NULL);

-- Verify the fix
SELECT 
  email,
  recovery_token IS NULL as rec_token_null,
  email_change_token_new IS NULL as email_change_token_new_null
FROM auth.users 
WHERE email IN ('thecraftsmanel@gmail.com', 'clydemflan@gmail.com')
ORDER BY email;
