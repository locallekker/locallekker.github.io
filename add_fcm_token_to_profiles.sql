-- Add FCM token column to profiles for push notifications when app is closed
-- This token is used by the Supabase Edge Function to send Firebase Cloud Messaging pushes

ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- Allow users to update their own FCM token
-- (The existing profiles RLS policies should already allow users to update their own row,
--  but adding this explicitly for clarity)
CREATE POLICY IF NOT EXISTS "Users can update own fcm_token"
ON profiles FOR UPDATE
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- Index for looking up tokens by user_id (used by the push notification edge function)
CREATE INDEX IF NOT EXISTS idx_profiles_fcm_token ON profiles (id) WHERE fcm_token IS NOT NULL;
