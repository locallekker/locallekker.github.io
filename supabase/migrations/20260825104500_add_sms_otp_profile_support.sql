-- Add canonical database support for SMS OTP verification state.
-- Keeps profile-level phone verification aligned with Supabase Auth.

BEGIN;

-- 1) Add profile columns used to track SMS OTP verification state.
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS phone_e164 TEXT;

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS sms_verified BOOLEAN;

-- 2) Set a safe default for newly created rows.
ALTER TABLE public.profiles
ALTER COLUMN sms_verified SET DEFAULT FALSE;

-- 3) Backfill profiles from auth.users where a phone identity exists.
UPDATE public.profiles p
SET phone_e164 = au.phone
FROM auth.users au
WHERE p.id = au.id
  AND au.phone IS NOT NULL
  AND btrim(au.phone) <> ''
  AND (p.phone_e164 IS NULL OR btrim(p.phone_e164) = '');

-- 4) Reconcile sms_verified from auth confirmation state.
UPDATE public.profiles p
SET sms_verified = (au.phone_confirmed_at IS NOT NULL)
FROM auth.users au
WHERE p.id = au.id
  AND au.phone IS NOT NULL
  AND btrim(au.phone) <> '';

-- 5) Fill remaining nulls for deterministic boolean behavior.
UPDATE public.profiles
SET sms_verified = FALSE
WHERE sms_verified IS NULL;

-- 6) Add indexes for SMS OTP lookups and filtering.
CREATE INDEX IF NOT EXISTS idx_profiles_sms_verified
ON public.profiles (sms_verified);

CREATE INDEX IF NOT EXISTS idx_profiles_phone_e164
ON public.profiles (phone_e164)
WHERE phone_e164 IS NOT NULL;

COMMIT;
