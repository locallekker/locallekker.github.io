-- Migration: Add member terms acceptance columns and RPC function
-- Ensures the three columns exist and provides a SECURITY DEFINER RPC so that
-- any valid authenticated user can record their own terms acceptance regardless
-- of the current RLS policy state on the profiles table.

-- 1. Add columns (idempotent)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS member_terms_accepted     BOOLEAN      DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS member_terms_accepted_at  TIMESTAMPTZ  NULL,
  ADD COLUMN IF NOT EXISTS member_terms_version      TEXT         NULL;

COMMENT ON COLUMN public.profiles.member_terms_accepted    IS 'True when member accepted the Member Terms & Conditions.';
COMMENT ON COLUMN public.profiles.member_terms_accepted_at IS 'Timestamp when member terms acceptance was recorded.';
COMMENT ON COLUMN public.profiles.member_terms_version     IS 'Version string of the terms accepted by the member.';

-- 2. Index to quickly find members who still need to accept
CREATE INDEX IF NOT EXISTS idx_profiles_member_terms_unaccepted
  ON public.profiles (id)
  WHERE member_terms_accepted = FALSE AND role = 'member';

-- 3. RPC: accept_member_terms
-- SECURITY DEFINER ensures the update succeeds even when the calling user's
-- RLS policies would otherwise block it.  The function validates that the
-- caller is updating only their own row, so there is no privilege escalation.
CREATE OR REPLACE FUNCTION public.accept_member_terms(
  p_user_id      UUID,
  p_version      TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Enforce that the caller can only update their own acceptance
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot accept terms for another user';
  END IF;

  UPDATE public.profiles
  SET
    member_terms_accepted    = TRUE,
    member_terms_accepted_at = NOW(),
    member_terms_version     = p_version,
    updated_at               = NOW()
  WHERE id = p_user_id;

  RETURN FOUND;
END;
$$;

-- Grant execute to authenticated users only
REVOKE ALL ON FUNCTION public.accept_member_terms(UUID, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.accept_member_terms(UUID, TEXT) TO authenticated;
