-- Compare ALL auth.users fields to find remaining NULL differences
SELECT 
  email,
  confirmation_token IS NULL as conf_token_null,
  recovery_token IS NULL as rec_token_null,
  email_change IS NULL as email_change_null,
  email_change_token_new IS NULL as email_change_token_new_null,
  email_change_token_current IS NULL as email_change_token_current_null,
  reauthentication_token IS NULL as reauth_token_null,
  phone_change IS NULL as phone_change_null,
  phone_change_token IS NULL as phone_change_token_null
FROM auth.users 
WHERE email IN ('thecraftsmanel@gmail.com', 'clydemflan@gmail.com')
ORDER BY email;
