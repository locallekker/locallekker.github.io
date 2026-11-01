-- Create calibration_receipts table for trusted partner receipt calibration
-- This table stores the text blocks and layout data from calibration receipts
-- to enable automatic identification of trusted partners when members scan receipts

CREATE TABLE IF NOT EXISTS calibration_receipts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    business_name TEXT NOT NULL,
    receipt_url TEXT NOT NULL,
    text_blocks JSONB NOT NULL, -- Array of text block objects with text, x, y, width, height
    layout_data JSONB NOT NULL, -- Layout bounds and metadata for matching
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_calibration_receipts_business_id ON calibration_receipts(business_id);
CREATE INDEX IF NOT EXISTS idx_calibration_receipts_active ON calibration_receipts(is_active);
CREATE INDEX IF NOT EXISTS idx_calibration_receipts_uploaded_at ON calibration_receipts(uploaded_at DESC);

-- Add RLS policies
ALTER TABLE calibration_receipts ENABLE ROW LEVEL SECURITY;

-- Policy: Business owners can view and manage their own calibration receipts
CREATE POLICY "Business owners can manage their calibration receipts"
ON calibration_receipts
FOR ALL
USING (business_id = auth.uid());

-- Policy: Members can view active calibration receipts for matching (read-only)
CREATE POLICY "Members can view active calibration receipts"
ON calibration_receipts
FOR SELECT
USING (is_active = true);

-- Policy: Allow service role to manage all calibration receipts (for background processing)
CREATE POLICY "Service role can manage all calibration receipts"
ON calibration_receipts
FOR ALL
USING (auth.role() = 'service_role');

-- Add comments for documentation
COMMENT ON TABLE calibration_receipts IS 'Stores calibration receipt data for automatic trusted partner identification';
COMMENT ON COLUMN calibration_receipts.text_blocks IS 'JSON array of text blocks with position and content data';
COMMENT ON COLUMN calibration_receipts.layout_data IS 'Layout bounds and metadata for receipt matching';