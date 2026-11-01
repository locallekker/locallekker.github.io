-- Alternative: PostgreSQL function to delete auth user
-- This can be called instead of the Edge Function if needed

-- Note: This requires the postgres user to have admin privileges
-- which may not be available in hosted Supabase

CREATE OR REPLACE FUNCTION admin_delete_auth_user(target_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_id UUID;
  is_admin BOOLEAN := FALSE;
BEGIN
  -- Get the caller ID from the current session
  caller_id := auth.uid();

  -- Check if caller is admin
  SELECT EXISTS(
    SELECT 1 FROM admin_dashboard WHERE admin_user_id = caller_id
  ) INTO is_admin;

  IF NOT is_admin THEN
    RAISE EXCEPTION 'Access denied: caller is not an admin';
  END IF;

  -- Delete from auth.users (requires admin privileges)
  -- Note: This may not work in hosted Supabase due to security restrictions
  DELETE FROM auth.users WHERE id = target_user_id;

  IF FOUND THEN
    RETURN json_build_object('success', true, 'user_id', target_user_id);
  ELSE
    RAISE EXCEPTION 'User % not found in auth.users', target_user_id;
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to delete auth user: %', SQLERRM;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION admin_delete_auth_user(UUID) TO authenticated;

-- Usage in AdminService (alternative to Edge Function):
-- await supabase.rpc('admin_delete_auth_user', params: {'target_user_id': userId});