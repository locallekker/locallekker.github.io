-- Fix Trusted Partner verified flags based on actual T&C acceptance and subscription status

-- 1. Roger Galloway: Not accepted terms, should NOT be verified
UPDATE profiles 
SET verified = false 
WHERE id = '857a6e51-c965-4fec-890c-61a08b1224c6' 
  AND email = 'emailheartwood@gmail.com'
  AND partner_terms_accepted = false;

-- 2. Michele Coetzer: Accepted terms, is TP member, active subscription, SHOULD be verified
UPDATE profiles 
SET verified = true 
WHERE id = 'aec73b0f-f8e1-4f1a-9c55-b1d6c4df808b' 
  AND email = 'michelebekker007@gmail.com'
  AND partner_terms_accepted = true
  AND is_tp_member = true
  AND subscription = 'active';

-- Verify the fixes
SELECT 
  'After Fix' as status,
  email,
  name,
  partner_terms_accepted,
  subscription,
  verified,
  is_tp_member
FROM profiles
WHERE email IN ('emailheartwood@gmail.com', 'michelebekker007@gmail.com')
ORDER BY email;
