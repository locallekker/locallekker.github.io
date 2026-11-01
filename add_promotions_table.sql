-- ============================================================
-- Migration: promotions & promotion_signups tables
-- Admin creates promotional campaigns (e.g. badminton event = 2 months free).
-- Members sign up, admin confirms, subscription is extended.
-- ============================================================

-- 1) Create the promotions table
CREATE TABLE IF NOT EXISTS public.promotions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  image_url TEXT,
  free_months INTEGER,            -- NULL means lifetime / never expires
  starts_at TIMESTAMPTZ DEFAULT now(),
  ends_at TIMESTAMPTZ,            -- NULL means no end date
  is_active BOOLEAN DEFAULT true,
  created_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2) Create the promotion_signups table
CREATE TABLE IF NOT EXISTS public.promotion_signups (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  promotion_id UUID NOT NULL REFERENCES public.promotions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id),
  user_name TEXT,
  user_email TEXT,
  user_contact TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'cancelled')),
  confirmed_at TIMESTAMPTZ,
  confirmed_by UUID REFERENCES public.profiles(id),
  subscription_extended BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(promotion_id, user_id)
);

-- 3) Indexes
CREATE INDEX IF NOT EXISTS idx_promotions_is_active
  ON public.promotions(is_active);

CREATE INDEX IF NOT EXISTS idx_promotions_ends_at
  ON public.promotions(ends_at);

CREATE INDEX IF NOT EXISTS idx_promotion_signups_promotion_id
  ON public.promotion_signups(promotion_id);

CREATE INDEX IF NOT EXISTS idx_promotion_signups_user_id
  ON public.promotion_signups(user_id);

CREATE INDEX IF NOT EXISTS idx_promotion_signups_status
  ON public.promotion_signups(status);

-- 4) RLS for promotions
ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;

-- Admin full access
CREATE POLICY "admin_full_access_promotions"
  ON public.promotions
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Authenticated users can read active, non-expired promotions
CREATE POLICY "authenticated_read_active_promotions"
  ON public.promotions
  FOR SELECT
  USING (
    auth.role() = 'authenticated'
    AND is_active = true
    AND (ends_at IS NULL OR ends_at > now())
  );

-- 5) RLS for promotion_signups
ALTER TABLE public.promotion_signups ENABLE ROW LEVEL SECURITY;

-- Admin full access
CREATE POLICY "admin_full_access_promotion_signups"
  ON public.promotion_signups
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Members can read their own signups
CREATE POLICY "members_read_own_signups"
  ON public.promotion_signups
  FOR SELECT
  USING (auth.uid() = user_id);

-- Members can insert their own signups
CREATE POLICY "members_insert_own_signups"
  ON public.promotion_signups
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- 6) RPC: confirm_promo_signup
-- Admin confirms a signup, extends subscription, updates QR expiry
CREATE OR REPLACE FUNCTION public.confirm_promo_signup(
  p_signup_id UUID,
  p_admin_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $fn$
DECLARE
  v_user_id UUID;
  v_signup_status TEXT;
  v_promotion_id UUID;
  v_free_months INTEGER;
  v_sub_id UUID;
  v_current_end TIMESTAMPTZ;
  v_new_end TIMESTAMPTZ;
BEGIN
  -- Verify admin role
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_admin_id AND role = 'admin'
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Not authorized');
  END IF;

  -- Get signup record fields
  SELECT ps.user_id, ps.status, ps.promotion_id
  INTO v_user_id, v_signup_status, v_promotion_id
  FROM public.promotion_signups ps
  WHERE ps.id = p_signup_id;

  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Signup not found');
  END IF;

  IF v_signup_status = 'confirmed' THEN
    RETURN json_build_object('success', false, 'error', 'Already confirmed');
  END IF;

  -- Get promotion free_months
  SELECT p.free_months
  INTO v_free_months
  FROM public.promotions p
  WHERE p.id = v_promotion_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Promotion not found');
  END IF;

  -- Get the member's latest subscription
  SELECT s.id, s.current_period_end
  INTO v_sub_id, v_current_end
  FROM public.subscriptions s
  WHERE s.user_id = v_user_id
  ORDER BY s.current_period_end DESC NULLS LAST
  LIMIT 1;

  IF v_sub_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'No subscription found for member');
  END IF;

  -- Calculate new end date
  IF v_free_months IS NULL THEN
    v_new_end := GREATEST(v_current_end, now()) + INTERVAL '100 years';
  ELSE
    v_new_end := GREATEST(v_current_end, now()) + (v_free_months || ' months')::INTERVAL;
  END IF;

  -- Extend subscription
  UPDATE public.subscriptions
  SET current_period_end = v_new_end,
      status = 'active',
      updated_at = now()
  WHERE id = v_sub_id;

  -- Extend QR code expiry to match
  UPDATE public.user_qr_codes
  SET expires_at = v_new_end,
      is_active = true,
      updated_at = now()
  WHERE user_id = v_user_id
    AND is_active = true;

  -- Mark signup as confirmed
  UPDATE public.promotion_signups
  SET status = 'confirmed',
      confirmed_at = now(),
      confirmed_by = p_admin_id,
      subscription_extended = true
  WHERE id = p_signup_id;

  RETURN json_build_object(
    'success', true,
    'new_period_end', v_new_end,
    'free_months', v_free_months,
    'member_id', v_user_id
  );
END;
$fn$;

-- 7) Storage bucket for promo images
-- Run this in Supabase Dashboard > Storage:
-- CREATE BUCKET 'promo-images' (public = true)
-- Or via SQL:
INSERT INTO storage.buckets (id, name, public)
VALUES ('promo-images', 'promo-images', true)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS: anyone can read
CREATE POLICY "public_read_promo_images"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'promo-images');

-- Storage RLS: admin can upload
CREATE POLICY "admin_upload_promo_images"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'promo-images'
    AND EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Storage RLS: admin can delete
CREATE POLICY "admin_delete_promo_images"
  ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'promo-images'
    AND EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );
