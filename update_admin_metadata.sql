UPDATE auth.users SET raw_user_meta_data = raw_user_meta_data || '{\
user_type\: \admin\}' WHERE email = 'admin@locallekker.com';
