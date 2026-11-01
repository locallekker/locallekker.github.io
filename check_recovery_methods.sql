-- Check recovery emails sent manually vs from app
-- Compare the timestamps and methods

SELECT 
  email,
  recovery_sent_at,
  email_confirmed_at,
  updated_at,
  raw_user_meta_data
FROM auth.users 
WHERE email IN ('thecraftsmanel@gmail.com', 'clydemflan@gmail.com')
ORDER BY updated_at DESC;

-- Also check recovery_sessions table to see which were created manually vs by app
SELECT 
  id,
  email,
  created_at,
  expires_at,
  used,
  user_id
FROM public.recovery_sessions
WHERE email IN ('thecraftsmanel@gmail.com', 'clydemflan@gmail.com')
ORDER BY created_at DESC
LIMIT 10;
