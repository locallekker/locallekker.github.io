-- Test if the create_recovery_session RPC works directly
SELECT public.create_recovery_session(
  (SELECT id FROM auth.users WHERE email = 'clydemflan@gmail.com'),
  'clydemflan@gmail.com'
);

-- Then check if it was created
SELECT 
  id,
  email,
  created_at,
  user_id
FROM public.recovery_sessions
WHERE email = 'clydemflan@gmail.com'
ORDER BY created_at DESC
LIMIT 3;
