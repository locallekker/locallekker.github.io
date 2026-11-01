-- Fix NULL email_change field for admin-created user
-- Supabase auth service expects empty string, not NULL

UPDATE auth.users 
SET email_change = ''
WHERE email = 'thecraftsmanel@gmail.com' 
  AND email_change IS NULL;

-- Verify the fix
SELECT 
  email, 
  email_change,
  email_change IS NULL as is_null
FROM auth.users 
WHERE email IN ('thecraftsmanel@gmail.com', 'clydemflan@gmail.com')
ORDER BY email;
