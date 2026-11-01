-- Add support for once-off deals that can only be redeemed once per member
ALTER TABLE trusted_partner_discounts
  ADD COLUMN IF NOT EXISTS is_once_off BOOLEAN DEFAULT FALSE;

-- Speed up filtering for once-off deals in queries
CREATE INDEX IF NOT EXISTS idx_trusted_partner_discounts_is_once_off
  ON trusted_partner_discounts (is_once_off);
