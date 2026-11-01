-- Fix existing admin-created users to enable password reset emails
-- Sets confirmation_sent_at so Supabase will send password recovery

UPDATE auth.users
SET confirmation_sent_at = email_confirmed_at
WHERE confirmation_sent_at IS NULL
  AND email_confirmed_at IS NOT NULL
  AND raw_user_meta_data->>'admin_created' = 'true';

-- Verify the fix
SELECT 
  email,
  email_confirmed_at,
  confirmation_sent_at,
  recovery_sent_at,
  raw_user_meta_data->>'admin_created' as admin_created
FROM auth.users
WHERE email = 'thecraftsmanel@gmail.com';
