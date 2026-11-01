-- Add schedule_data column to trusted_partner_discounts table
-- This allows deals to be scheduled for specific date ranges or days of the week

BEGIN;

-- Add schedule_data column as JSONB to store scheduling information
ALTER TABLE public.trusted_partner_discounts
ADD COLUMN IF NOT EXISTS schedule_data JSONB;

-- Add comment for clarity
COMMENT ON COLUMN public.trusted_partner_discounts.schedule_data IS 'JSON data for deal scheduling: {type: "none"|"dateRange"|"dayOfWeek", start_date, end_date, day_of_week, is_recurring}';

-- Create index for better query performance on scheduled deals
CREATE INDEX IF NOT EXISTS idx_trusted_partner_discounts_schedule
ON public.trusted_partner_discounts USING GIN (schedule_data);

COMMIT;
