-- =============================================================================
-- LOCAL LEKKER: Create prepare_user_context() RPC Function
-- Run this in Supabase SQL Editor
-- =============================================================================
-- This SECURITY DEFINER function ensures a profile row exists for the
-- authenticated user. The app calls it during login; if it's missing,
-- the app falls back to a client-side upsert (which may be blocked by RLS).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.prepare_user_context()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid;
  v_email text;
BEGIN
  -- Get the authenticated user's ID and email from the JWT
  v_uid   := auth.uid();
  v_email := auth.jwt() ->> 'email';

  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  -- Ensure a profile row exists (insert if missing, do nothing if present)
  INSERT INTO public.profiles (id, email, created_at, updated_at)
  VALUES (
    v_uid,
    COALESCE(v_email, ''),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN jsonb_build_object('ok', true, 'user_id', v_uid);
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.prepare_user_context() TO authenticated;
