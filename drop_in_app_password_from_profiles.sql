-- Migration: Drop deprecated in_app_password column from profiles
-- Reason: Replaced by OTP-verified Change Password flow; storing plaintext in-app password is insecure
-- Safe to run multiple times

ALTER TABLE profiles
  DROP COLUMN IF EXISTS in_app_password;
