-- Add key_used_by column to trusted_partners to track single-use promo keys
-- When a member uses a TP's promo key, their user_id is stored here
-- A non-null value means the key has already been claimed

ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS key_used_by UUID REFERENCES public.profiles(id);

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_trusted_partners_key_used_by 
ON public.trusted_partners(key_used_by) WHERE key_used_by IS NOT NULL;
