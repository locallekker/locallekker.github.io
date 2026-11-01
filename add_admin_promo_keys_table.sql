-- ============================================================
-- Migration: admin_promo_keys table
-- Allows admin to generate email-locked promo keys with
-- configurable subscription duration for members.
-- ============================================================

-- 1) Create the table
CREATE TABLE IF NOT EXISTS public.admin_promo_keys (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  key TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL,
  duration_months INTEGER,  -- NULL means all-time / never expires
  used_by UUID REFERENCES public.profiles(id),
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  created_by UUID REFERENCES public.profiles(id)
);

-- 2) Indexes
CREATE INDEX IF NOT EXISTS idx_admin_promo_keys_key
  ON public.admin_promo_keys(key);

CREATE INDEX IF NOT EXISTS idx_admin_promo_keys_email
  ON public.admin_promo_keys(email);

CREATE UNIQUE INDEX IF NOT EXISTS idx_admin_promo_keys_used_by
  ON public.admin_promo_keys(used_by) WHERE used_by IS NOT NULL;

-- 3) RLS
ALTER TABLE public.admin_promo_keys ENABLE ROW LEVEL SECURITY;

-- Admin can do everything
CREATE POLICY "admin_full_access_admin_promo_keys"
  ON public.admin_promo_keys
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

-- Authenticated users can read (needed for key validation during signup)
CREATE POLICY "authenticated_read_admin_promo_keys"
  ON public.admin_promo_keys
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- Authenticated users can update (mark key as used during activation)
CREATE POLICY "authenticated_update_admin_promo_keys"
  ON public.admin_promo_keys
  FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');
