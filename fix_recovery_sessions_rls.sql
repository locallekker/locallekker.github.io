-- Fix recovery_sessions RLS to allow anon users to read active sessions
-- (needed for app to detect password recovery on startup)

-- Drop existing policies if any
DROP POLICY IF EXISTS "Users can read own recovery sessions" ON public.recovery_sessions;
DROP POLICY IF EXISTS "Anyone can insert recovery session" ON public.recovery_sessions;

-- Create new policies
CREATE POLICY "Anyone can insert recovery session"
  ON public.recovery_sessions
  FOR INSERT
  WITH CHECK (true);

-- Allow anyone to read active recovery sessions (needed for app startup check)
CREATE POLICY "Anyone can read active recovery sessions"
  ON public.recovery_sessions
  FOR SELECT
  USING (used = false AND expires_at > NOW());

-- Verify policies exist
SELECT tablename, policyname 
FROM pg_policies 
WHERE tablename = 'recovery_sessions'
ORDER BY policyname;
