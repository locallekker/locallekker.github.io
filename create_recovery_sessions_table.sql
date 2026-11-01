-- Create recovery_sessions table to track password reset attempts
-- This allows the app to detect when a user should be in password reset mode

CREATE TABLE IF NOT EXISTS public.recovery_sessions (
  id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL,
  token text NOT NULL,
  created_at timestamp with time zone DEFAULT NOW(),
  expires_at timestamp with time zone DEFAULT NOW() + interval '1 hour',
  used boolean DEFAULT false
);

-- Enable RLS
ALTER TABLE public.recovery_sessions ENABLE ROW LEVEL SECURITY;

-- Anyone can insert their own recovery session
CREATE POLICY "Anyone can insert recovery session"
  ON public.recovery_sessions
  FOR INSERT
  WITH CHECK (true);

-- Users can read their own recovery sessions
CREATE POLICY "Users can read own recovery sessions"
  ON public.recovery_sessions
  FOR SELECT
  USING (auth.uid() = user_id OR email = auth.jwt()->>'email');

-- When user initiates password reset via "Send password recovery" in Supabase dashboard,
-- insert a row here via a trigger or manually
-- The app will check this table on startup to detect password reset mode

-- For testing: insert a recovery session manually
-- INSERT INTO public.recovery_sessions (user_id, email, token)
-- VALUES ((SELECT id FROM auth.users WHERE email = 'clydemflan@gmail.com'), 'clydemflan@gmail.com', 'test_token');
