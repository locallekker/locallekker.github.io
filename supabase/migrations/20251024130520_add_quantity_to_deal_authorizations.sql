-- Add quantity column to deal_authorizations table for weight-based deals
ALTER TABLE deal_authorizations ADD COLUMN IF NOT EXISTS quantity INTEGER;
