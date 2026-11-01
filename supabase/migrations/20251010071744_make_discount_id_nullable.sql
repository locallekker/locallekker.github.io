-- Make discount_id nullable to allow bills without discounts when manually selecting trusted partners
ALTER TABLE processed_bills ALTER COLUMN discount_id DROP NOT NULL;
