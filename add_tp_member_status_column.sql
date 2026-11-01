-- =====================================================
-- ADD TP_MEMBER_STATUS COLUMN TO TRUSTED_PARTNERS
-- Track when TPs activate their member privileges
-- =====================================================

-- Add tp_member_status column to trusted_partners table
ALTER TABLE trusted_partners
ADD COLUMN IF NOT EXISTS tp_member_status TEXT DEFAULT 'inactive';

-- Add check constraint for valid values
ALTER TABLE trusted_partners
DROP CONSTRAINT IF EXISTS tp_member_status_check;

ALTER TABLE trusted_partners
ADD CONSTRAINT tp_member_status_check 
CHECK (tp_member_status IN ('active', 'inactive'));

-- Add index for filtering active TP members
CREATE INDEX IF NOT EXISTS idx_trusted_partners_tp_member_status 
ON trusted_partners(tp_member_status) WHERE tp_member_status = 'active';

-- Add comment
COMMENT ON COLUMN trusted_partners.tp_member_status IS 
'Status of TP member privileges: active (TP has activated member access with 100-year QR code), inactive (TP only, no member access)';

-- Set existing TP with is_tp_member flag to active
UPDATE trusted_partners
SET tp_member_status = 'active'
WHERE user_id IN (
  SELECT id FROM profiles WHERE is_tp_member = true
);

-- Verify the changes
SELECT 
  tp.user_id,
  p.name,
  p.surname,
  p.email,
  tp.business_name,
  tp.tp_member_status,
  p.is_tp_member,
  tp.created_at
FROM trusted_partners tp
LEFT JOIN profiles p ON tp.user_id = p.id
ORDER BY tp.created_at DESC;
