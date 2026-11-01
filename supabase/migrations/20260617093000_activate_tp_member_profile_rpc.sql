-- ============================================================
-- Migration: activate_tp_member_profile RPC
-- Updates TP-member state through a SECURITY DEFINER function so
-- client-side activation does not hit recursive RLS policies on
-- profiles / memberships / trusted_partners.
-- ============================================================

CREATE OR REPLACE FUNCTION public.activate_tp_member_profile(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.profiles
  SET is_tp_member = true
  WHERE id = p_user_id;

  UPDATE public.trusted_partners
  SET tp_member_status = 'active'
  WHERE user_id = p_user_id;

  INSERT INTO public.memberships (user_id, role, gateway)
  VALUES (p_user_id, 'member', 'trusted_partner_key')
  ON CONFLICT (user_id) DO UPDATE
    SET gateway = EXCLUDED.gateway,
        role = CASE
          WHEN public.memberships.role IN ('trusted_partner', 'admin') THEN public.memberships.role
          ELSE EXCLUDED.role
        END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.activate_tp_member_profile(UUID) TO authenticated;