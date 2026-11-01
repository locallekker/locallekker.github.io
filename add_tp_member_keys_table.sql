-- ============================================================
-- Migration: tp_member_keys table
-- Allows admin to issue multiple single-use activation keys
-- per trusted partner for activating TP member profiles.
-- ============================================================

-- 1) Create the table
CREATE TABLE IF NOT EXISTS public.tp_member_keys (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  trusted_partner_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  key TEXT NOT NULL UNIQUE,
  used_by UUID REFERENCES public.profiles(id),
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  created_by UUID REFERENCES public.profiles(id)
);

-- 2) Indexes
CREATE INDEX IF NOT EXISTS idx_tp_member_keys_tp_id
  ON public.tp_member_keys(trusted_partner_id);

CREATE INDEX IF NOT EXISTS idx_tp_member_keys_key
  ON public.tp_member_keys(key);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tp_member_keys_used_by
  ON public.tp_member_keys(used_by) WHERE used_by IS NOT NULL;

-- 3) RLS
ALTER TABLE public.tp_member_keys ENABLE ROW LEVEL SECURITY;

-- Admin can do everything
CREATE POLICY "admin_full_access_tp_member_keys"
  ON public.tp_member_keys
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

-- Authenticated users can read keys (needed for key validation during activation)
CREATE POLICY "authenticated_read_tp_member_keys"
  ON public.tp_member_keys
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- Authenticated users can update (mark key as used during activation)
CREATE POLICY "authenticated_update_tp_member_keys"
  ON public.tp_member_keys
  FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');
