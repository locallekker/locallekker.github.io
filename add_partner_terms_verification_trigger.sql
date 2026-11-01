-- Migration: Add trigger to auto-verify TP when they accept terms
-- This ensures that when a trusted partner accepts terms, they're automatically marked as verified

CREATE OR REPLACE FUNCTION public.on_partner_terms_accepted()
RETURNS TRIGGER AS $$
BEGIN
  -- When partner_terms_accepted changes from false to true, set verified=true
  IF NEW.partner_terms_accepted = true AND OLD.partner_terms_accepted != true THEN
    NEW.verified := true;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS on_partner_terms_accepted_trigger ON public.profiles;

-- Create trigger
CREATE TRIGGER on_partner_terms_accepted_trigger
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.on_partner_terms_accepted();

-- Also handle case where admin creates TP with verified flag
-- If role is 'trusted_partner' and partner_terms_accepted is true, ensure verified is true
CREATE OR REPLACE FUNCTION public.enforce_partner_verification()
RETURNS TRIGGER AS $$
BEGIN
  -- For trusted partners, verified should follow partner_terms_accepted
  IF NEW.role = 'trusted_partner' THEN
    IF NEW.partner_terms_accepted = true THEN
      NEW.verified := true;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS enforce_partner_verification_trigger ON public.profiles;

-- Create trigger (this runs after the terms trigger)
CREATE TRIGGER enforce_partner_verification_trigger
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.enforce_partner_verification();

-- Test: Verify that That Old Oak would be marked as verified if they accepted terms
SELECT 
  id,
  email,
  name,
  role,
  verified,
  partner_terms_accepted,
  CASE 
    WHEN role = 'trusted_partner' AND partner_terms_accepted = true THEN 'Should be VERIFIED'
    ELSE 'Not applicable'
  END as expected_status
FROM profiles
WHERE role = 'trusted_partner' AND (email ILIKE '%craft%' OR name ILIKE '%oak%')
LIMIT 5;
