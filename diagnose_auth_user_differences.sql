-- Compare all auth.users fields between working and non-working users
SELECT 
  email,
  email_confirmed_at IS NOT NULL as has_email_confirmed,
  confirmation_sent_at IS NOT NULL as has_confirmation_sent,
  encrypted_password IS NOT NULL as has_password,
  LENGTH(encrypted_password) as password_length,
  SUBSTRING(encrypted_password, 1, 10) as password_prefix,
  aud,
  role,
  instance_id,
  invited_at,
  confirmation_token,
  recovery_token,
  email_change_token_new,
  email_change,
  banned_until IS NOT NULL as is_banned,
  deleted_at IS NOT NULL as is_deleted,
  is_sso_user,
  raw_app_meta_data,
  raw_user_meta_data
FROM auth.users
WHERE email IN ('thecraftsmanel@gmail.com', 'clydemflan@gmail.com')
ORDER BY email;
