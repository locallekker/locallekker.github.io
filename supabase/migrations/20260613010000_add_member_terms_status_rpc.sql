-- Migration: SECURITY DEFINER read RPC for member terms acceptance status.
--
-- Rationale: The write side (accept_member_terms) is already SECURITY DEFINER,
-- but the dart app re-reads `profiles.member_terms_accepted` via a normal
-- table SELECT to decide which screen to show after the user accepts. If RLS
-- (or column-level policies, or transient errors) blocks that SELECT, the
-- app interprets the response as "not accepted" and bounces the user back to
-- the terms page, producing an infinite loop after pressing Save.
--
-- This RPC mirrors accept_member_terms in spirit: it bypasses RLS and lets a
-- user read their OWN acceptance flag (and only their own). It returns NULL
-- when the profile row does not exist so the caller can distinguish "missing"
-- from "explicitly false".

CREATE OR REPLACE FUNCTION public.member_terms_accepted_status(
  p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_accepted BOOLEAN;
BEGIN
  -- Only allow a user to read their own acceptance status.
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot read terms status for another user';
  END IF;

  SELECT member_terms_accepted
    INTO v_accepted
  FROM public.profiles
  WHERE id = p_user_id;

  -- COALESCE NULL -> FALSE so callers get an explicit boolean when the row
  -- exists but the column was never set; NULL is returned only when no
  -- profile row exists at all.
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  RETURN COALESCE(v_accepted, FALSE);
END;
$$;

REVOKE ALL ON FUNCTION public.member_terms_accepted_status(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.member_terms_accepted_status(UUID) TO authenticated;
