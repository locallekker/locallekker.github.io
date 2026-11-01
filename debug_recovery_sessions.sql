-- Check if recovery sessions are being created when user clicks "Forgot password"
-- Look for recently created sessions

SELECT 
  id,
  email,
  created_at,
  expires_at,
  used,
  user_id
FROM public.recovery_sessions
ORDER BY created_at DESC
LIMIT 5;

-- Also check if the RLS policy allows reading them
-- (This query should work if RLS is correctly configured)
SELECT COUNT(*) as recovery_session_count
FROM public.recovery_sessions
WHERE used = false
AND expires_at > NOW();
