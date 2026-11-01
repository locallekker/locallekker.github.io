-- Create Test Member Account for Google Play Review
-- Email: reviewer@locallekker.test
-- Password: ReviewTest2026!

-- Run this in Supabase Dashboard > SQL Editor

-- First, check what valid roles exist
SELECT constraint_name, check_clause 
FROM information_schema.check_constraints 
WHERE constraint_name = 'valid_role';

-- Step 1: Temporarily disable trigger and create user manually
ALTER TABLE profiles DISABLE TRIGGER handle_new_user_role_assignment;

DO $$
DECLARE
  new_user_id uuid := gen_random_uuid();
BEGIN
  -- Insert auth user
  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change_token_new,
    recovery_token
  )
  VALUES (
    '00000000-0000-0000-0000-000000000000',
    new_user_id,
    'authenticated',
    'authenticated',
    'reviewer@locallekker.test',
    crypt('ReviewTest2026!', gen_salt('bf')),
    NOW(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    NOW(),
    NOW(),
    '',
    '',
    ''
  );

  -- Manually create profile with 'member' role
  INSERT INTO public.profiles (
    id,
    email,
    name,
    surname,
    role,
    created_at,
    updated_at
  )
  VALUES (
    new_user_id,
    'reviewer@locallekker.test',
    'Google',
    'Reviewer',
    'member',
    NOW(),
    NOW()
  );

  -- Create active subscription (30 days from now)
  INSERT INTO public.subscriptions (
    id,
    user_id,
    plan_type,
    status,
    start_date,
    end_date,
    is_active,
    created_at,
    updated_at
  )
  VALUES (
    gen_random_uuid(),
    new_user_id,
    'monthly',
    'active',
    NOW(),
    NOW() + INTERVAL '30 days',
    true,
    NOW(),
    NOW()
  );

  -- Create QR code for payments
  INSERT INTO public.user_qr_codes (
    id,
    user_id,
    qr_code_data,
    is_active,
    expires_at,
    created_at,
    updated_at
  )
  VALUES (
    gen_random_uuid(),
    new_user_id,
    'REVIEWER_TEST_QR_' || new_user_id::text,
    true,
    NOW() + INTERVAL '30 days',
    NOW(),
    NOW()
  );

  RAISE NOTICE 'Test account created with ID: %', new_user_id;
END $$;

-- Re-enable trigger
ALTER TABLE profiles ENABLE TRIGGER handle_new_user_role_assignment;

-- Verification query - run this to confirm the test account was created
SELECT 
  p.id,
  p.email,
  p.name,
  p.surname,
  p.role,
  s.status as subscription_status,
  s.end_date as subscription_expires,
  qr.is_active as qr_active
FROM profiles p
LEFT JOIN subscriptions s ON s.user_id = p.id
LEFT JOIN user_qr_codes qr ON qr.user_id = p.id
WHERE p.email = 'reviewer@locallekker.test';
