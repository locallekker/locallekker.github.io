-- RPC to create a recovery session when password reset email is triggered
-- This should be called by the app or triggered by Supabase when recovery email is sent

CREATE OR REPLACE FUNCTION public.create_recovery_session(p_user_id uuid, p_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token text;
BEGIN
  -- Generate a random token
  v_token := extensions.gen_random_uuid()::text;
  
  -- Clean up old sessions for this user
  DELETE FROM public.recovery_sessions 
  WHERE user_id = p_user_id AND used = false;
  
  -- Insert new recovery session
  INSERT INTO public.recovery_sessions (user_id, email, token)
  VALUES (p_user_id, p_email, v_token);
  
  RETURN jsonb_build_object('ok', true, 'token', v_token);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_recovery_session(uuid, text) TO authenticated, anon;
