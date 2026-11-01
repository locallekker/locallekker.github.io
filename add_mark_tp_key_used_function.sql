-- ============================================================
-- Migration: mark_tp_key_used RPC function
-- Allows any authenticated user to mark a TP key as used
-- during promo key activation. Uses SECURITY DEFINER to
-- bypass RLS (members can't update trusted_partners rows
-- belonging to other users).
-- ============================================================

CREATE OR REPLACE FUNCTION public.mark_tp_key_used(p_key TEXT, p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Try tp_member_keys first
  UPDATE public.tp_member_keys
  SET used_by = p_user_id, used_at = NOW()
  WHERE key = p_key AND used_by IS NULL;

  IF NOT FOUND THEN
    -- Fall back to trusted_partners.unique_key
    UPDATE public.trusted_partners
    SET key_used_by = p_user_id
    WHERE unique_key = p_key AND key_used_by IS NULL;
  END IF;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.mark_tp_key_used(TEXT, UUID) TO authenticated;
