-- Check the actual password reset email template/URL that was sent
-- Query recovery_sent_at to confirm email was sent

SELECT 
  email,
  recovery_sent_at,
  recovery_token,
  recovery_token = '' as token_is_empty,
  recovery_token IS NULL as token_is_null
FROM auth.users 
WHERE email = 'clydemflan@gmail.com';
