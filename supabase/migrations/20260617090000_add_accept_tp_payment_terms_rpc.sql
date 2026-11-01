-- Migration: Add SECURITY DEFINER RPC for Trusted Partner payment terms acceptance
-- Fixes PostgrestException 42P17 (infinite recursion in profiles RLS policy) that
-- occurs when TpPaymentTermsPage does a direct client.from('profiles').update() call.
-- The same SECURITY DEFINER pattern is used by accept_partner_terms and accept_member_terms.

-- Ensure columns exist (idempotent)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS partner_payment_terms_accepted         BOOLEAN      DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS partner_payment_terms_accepted_at      TIMESTAMPTZ  NULL,
  ADD COLUMN IF NOT EXISTS partner_payment_terms_version          TEXT         NULL;

-- RPC: accept_tp_payment_terms
-- SECURITY DEFINER bypasses RLS on profiles so the update never hits the
-- infinite-recursion policy. The function validates the caller is updating
-- only their own row via auth.uid() = p_user_id to prevent privilege escalation.
CREATE OR REPLACE FUNCTION public.accept_tp_payment_terms(
  p_user_id  UUID,
  p_version  TEXT DEFAULT 'v2026-04-13'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Prevent users from updating someone else's row
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: caller may only accept terms for their own profile';
  END IF;

  UPDATE public.profiles
  SET
    partner_payment_terms_accepted    = TRUE,
    partner_payment_terms_accepted_at = NOW(),
    partner_payment_terms_version     = p_version
  WHERE id = p_user_id;

  RETURN FOUND;
END;
$$;

-- Allow any authenticated user to call this RPC (the body enforces ownership)
GRANT EXECUTE ON FUNCTION public.accept_tp_payment_terms(UUID, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.accept_tp_payment_terms(UUID, TEXT) FROM anon;
