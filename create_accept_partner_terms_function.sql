-- Create a function that allows a trusted partner to accept terms and automatically gets verified
-- This bypasses the RLS on the verified field since it uses SECURITY DEFINER

CREATE OR REPLACE FUNCTION public.accept_partner_terms(
  user_id UUID,
  terms_version TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
  user_role TEXT;
  user_itp_member BOOLEAN;
BEGIN
  -- Verify the user is authenticated (caller must be the same user)
  IF auth.uid() != user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot accept terms for another user';
  END IF;

  -- Get the user's role and is_tp_member flag
  SELECT role, is_tp_member
  INTO user_role, user_itp_member
  FROM public.profiles
  WHERE id = user_id;

  -- Verify user is a trusted partner
  IF user_role IS NULL THEN
    RAISE EXCEPTION 'User profile not found';
  END IF;

  IF user_role != 'trusted_partner' THEN
    RAISE EXCEPTION 'User is not a trusted partner';
  END IF;

  -- Update partner terms acceptance
  UPDATE public.profiles
  SET 
    partner_terms_accepted = true,
    partner_terms_accepted_at = NOW(),
    partner_terms_version = terms_version,
    updated_at = NOW()
  WHERE id = user_id;

  -- Now set verified = true (this bypasses RLS due to SECURITY DEFINER)
  UPDATE public.profiles
  SET 
    verified = true,
    updated_at = NOW()
  WHERE id = user_id AND role = 'trusted_partner' AND partner_terms_accepted = true;

  RETURN true;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Error in accept_partner_terms: %', SQLERRM;
  RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.accept_partner_terms(UUID, TEXT) TO authenticated;

-- Test the function (replace with actual user UUID)
-- SELECT public.accept_partner_terms('user-uuid-here', 'v2025-11-10');
