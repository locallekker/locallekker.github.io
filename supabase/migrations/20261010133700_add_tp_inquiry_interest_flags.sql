ALTER TABLE public.tp_inquiries
  ADD COLUMN IF NOT EXISTS sells_fresh_produce BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sells_alcohol BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS offers_sports_activities BOOLEAN NOT NULL DEFAULT false;
