-- ============================================================
-- Intro campaign promotions (R1 now, free months, then R99 auto-renew)
-- ============================================================

-- 1) Extend promotions with intro-billing metadata
ALTER TABLE public.promotions
ADD COLUMN IF NOT EXISTS is_intro_campaign BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS initial_charge_cents INTEGER DEFAULT 100,
ADD COLUMN IF NOT EXISTS renewal_charge_cents INTEGER DEFAULT 9900;

-- Guard rails for cents values
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'promotions_initial_charge_cents_non_negative'
  ) THEN
    ALTER TABLE public.promotions
      ADD CONSTRAINT promotions_initial_charge_cents_non_negative
      CHECK (initial_charge_cents IS NULL OR initial_charge_cents >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'promotions_renewal_charge_cents_non_negative'
  ) THEN
    ALTER TABLE public.promotions
      ADD CONSTRAINT promotions_renewal_charge_cents_non_negative
      CHECK (renewal_charge_cents IS NULL OR renewal_charge_cents >= 0);
  END IF;
END $$;

-- 2) Campaign participant email allocations (admin-managed)
CREATE TABLE IF NOT EXISTS public.promotion_participant_emails (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  promotion_id UUID NOT NULL REFERENCES public.promotions(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  is_claimed BOOLEAN NOT NULL DEFAULT false,
  claimed_by UUID REFERENCES public.profiles(id),
  claimed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (promotion_id, email)
);

CREATE INDEX IF NOT EXISTS idx_promotion_participant_emails_lookup
  ON public.promotion_participant_emails(promotion_id, email);

CREATE INDEX IF NOT EXISTS idx_promotion_participant_emails_email
  ON public.promotion_participant_emails(email);

-- 3) Extend subscriptions with intro lifecycle fields
ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS promotion_id UUID REFERENCES public.promotions(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS promo_participant_id UUID REFERENCES public.promotion_participant_emails(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS initial_charge_cents INTEGER,
ADD COLUMN IF NOT EXISTS renewal_charge_cents INTEGER,
ADD COLUMN IF NOT EXISTS intro_charge_reference TEXT,
ADD COLUMN IF NOT EXISTS intro_charge_paid_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS free_period_end TIMESTAMPTZ;

-- 4) RLS for participant allocations
ALTER TABLE public.promotion_participant_emails ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_full_access_promotion_participant_emails" ON public.promotion_participant_emails;
CREATE POLICY "admin_full_access_promotion_participant_emails"
  ON public.promotion_participant_emails
  FOR ALL
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

DROP POLICY IF EXISTS "members_read_own_promotion_participant_eligibility" ON public.promotion_participant_emails;
CREATE POLICY "members_read_own_promotion_participant_eligibility"
  ON public.promotion_participant_emails
  FOR SELECT
  USING (
    auth.role() = 'authenticated'
    AND lower(email) = lower(coalesce((SELECT p.email FROM public.profiles p WHERE p.id = auth.uid()), ''))
  );

-- 5) Normalize email values at write-time
CREATE OR REPLACE FUNCTION public.normalize_promotion_participant_email()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.email := lower(trim(NEW.email));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalize_promotion_participant_email ON public.promotion_participant_emails;
CREATE TRIGGER trg_normalize_promotion_participant_email
BEFORE INSERT OR UPDATE ON public.promotion_participant_emails
FOR EACH ROW
EXECUTE FUNCTION public.normalize_promotion_participant_email();
