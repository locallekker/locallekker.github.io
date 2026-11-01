-- Add canonical database support for email OTP state in profiles.
-- This aligns app-side OTP verification flows with schema state.

BEGIN;

-- 1) Add email_verified column when missing.
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS email_verified BOOLEAN;

-- 2) Ensure a safe default for future records.
ALTER TABLE public.profiles
ALTER COLUMN email_verified SET DEFAULT TRUE;

-- 3) Backfill existing nulls so profile state is always explicit.
UPDATE public.profiles
SET email_verified = TRUE
WHERE email_verified IS NULL;

-- 4) Reconcile admin-created accounts against auth confirmation state.
-- If admin-created and still unconfirmed in auth.users, treat as not verified.
UPDATE public.profiles p
SET email_verified = FALSE
FROM auth.users au
WHERE p.id = au.id
  AND COALESCE(p.admin_created, FALSE) = TRUE
  AND au.email_confirmed_at IS NULL;

-- If confirmed in auth.users, keep profile flag consistent.
UPDATE public.profiles p
SET email_verified = TRUE
FROM auth.users au
WHERE p.id = au.id
  AND au.email_confirmed_at IS NOT NULL;

-- 5) Add indexes for common OTP/status lookups.
CREATE INDEX IF NOT EXISTS idx_profiles_email_verified
ON public.profiles (email_verified);

CREATE INDEX IF NOT EXISTS idx_profiles_email_email_verified
ON public.profiles (email, email_verified);

COMMIT;
