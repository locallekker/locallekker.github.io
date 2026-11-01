-- ============================================================
-- Migration Part 1: Tables, indexes, RLS policies
-- Run this FIRST in Supabase SQL Editor
-- ============================================================

-- 1) Create the promotions table
CREATE TABLE IF NOT EXISTS public.promotions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  image_url TEXT,
  free_months INTEGER,
  starts_at TIMESTAMPTZ DEFAULT now(),
  ends_at TIMESTAMPTZ,
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
CREATE INDEX IF NOT EXISTS idx_promotions_is_active ON public.promotions(is_active);
CREATE INDEX IF NOT EXISTS idx_promotions_ends_at ON public.promotions(ends_at);
CREATE INDEX IF NOT EXISTS idx_promotion_signups_promotion_id ON public.promotion_signups(promotion_id);
CREATE INDEX IF NOT EXISTS idx_promotion_signups_user_id ON public.promotion_signups(user_id);
CREATE INDEX IF NOT EXISTS idx_promotion_signups_status ON public.promotion_signups(status);

-- 4) RLS for promotions
ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_full_access_promotions"
  ON public.promotions FOR ALL
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "authenticated_read_active_promotions"
  ON public.promotions FOR SELECT
  USING (auth.role() = 'authenticated' AND is_active = true AND (ends_at IS NULL OR ends_at > now()));

-- 5) RLS for promotion_signups
ALTER TABLE public.promotion_signups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_full_access_promotion_signups"
  ON public.promotion_signups FOR ALL
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "members_read_own_signups"
  ON public.promotion_signups FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "members_insert_own_signups"
  ON public.promotion_signups FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- 6) Storage bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('promo-images', 'promo-images', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "public_read_promo_images"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'promo-images');

CREATE POLICY "admin_upload_promo_images"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'promo-images' AND EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "admin_delete_promo_images"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'promo-images' AND EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));
