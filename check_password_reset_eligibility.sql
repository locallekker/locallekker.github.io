-- Check why admin-created user can't receive password reset emails
-- Run this in Supabase SQL Editor

SELECT 
  au.id,
  au.email,
  au.email_confirmed_at,
  au.confirmation_sent_at,
  au.recovery_sent_at,
  au.email_change_sent_at,
  au.banned_until,
  au.deleted_at,
  au.raw_user_meta_data->>'email_verified' as meta_email_verified,
  au.raw_user_meta_data->>'admin_created' as meta_admin_created,
  p.email_verified as profile_email_verified,
  p.admin_created as profile_admin_created
FROM auth.users au
LEFT JOIN public.profiles p ON au.id = p.id
WHERE au.email IN ('thecraftsmanel@gmail.com', 'clydemflan@gmail.com')
ORDER BY au.email;
