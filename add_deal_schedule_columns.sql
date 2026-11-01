-- Add schedule-related columns to trusted_partner_discounts table

-- Schedule type: 'always', 'daily', 'specific_days', 'date_range'
ALTER TABLE trusted_partner_discounts 
ADD COLUMN IF NOT EXISTS schedule_type TEXT DEFAULT 'always';

-- For specific_days: JSON array of day schedules
-- Format: [{"day": "monday", "allDay": true, "startTime": null, "endTime": null, "recurring": true}, ...]
ALTER TABLE trusted_partner_discounts 
ADD COLUMN IF NOT EXISTS schedule_days JSONB DEFAULT '[]'::jsonb;

-- For date_range: start and end dates
ALTER TABLE trusted_partner_discounts 
ADD COLUMN IF NOT EXISTS schedule_start_date TIMESTAMPTZ;

ALTER TABLE trusted_partner_discounts 
ADD COLUMN IF NOT EXISTS schedule_end_date TIMESTAMPTZ;

-- For date_range: start and end times (stored as time strings like "09:00", "17:00")
ALTER TABLE trusted_partner_discounts 
ADD COLUMN IF NOT EXISTS schedule_start_time TEXT;

ALTER TABLE trusted_partner_discounts 
ADD COLUMN IF NOT EXISTS schedule_end_time TEXT;

-- Comment explaining the schedule system
COMMENT ON COLUMN trusted_partner_discounts.schedule_type IS 
'Schedule type: always (default, always active), daily (active every day), specific_days (active on selected days), date_range (active between dates)';

COMMENT ON COLUMN trusted_partner_discounts.schedule_days IS 
'JSON array of day schedules for specific_days type. Example: [{"day": "monday", "allDay": true, "startTime": null, "endTime": null, "recurring": true}]';

-- Create index for schedule queries
CREATE INDEX IF NOT EXISTS idx_discounts_schedule_dates 
ON trusted_partner_discounts(schedule_start_date, schedule_end_date) 
WHERE schedule_type = 'date_range';

-- Function to check if a deal is currently active based on schedule
CREATE OR REPLACE FUNCTION is_deal_active_now(
    p_is_active BOOLEAN,
    p_schedule_type TEXT,
    p_schedule_days JSONB,
    p_schedule_start_date TIMESTAMPTZ,
    p_schedule_end_date TIMESTAMPTZ,
    p_schedule_start_time TEXT,
    p_schedule_end_time TEXT
) RETURNS BOOLEAN AS $$
DECLARE
    v_now TIMESTAMPTZ := NOW();
    v_current_day TEXT;
    v_current_time TEXT;
    v_day_schedule JSONB;
BEGIN
    -- If not active at all, return false
    IF NOT p_is_active THEN
        RETURN FALSE;
    END IF;

    -- If always active, return true
    IF p_schedule_type = 'always' OR p_schedule_type IS NULL THEN
        RETURN TRUE;
    END IF;

    -- If daily (24/7), return true
    IF p_schedule_type = 'daily' THEN
        RETURN TRUE;
    END IF;

    -- If date_range, check if current date/time is within range
    IF p_schedule_type = 'date_range' THEN
        -- Check date range
        IF p_schedule_start_date IS NOT NULL AND v_now < p_schedule_start_date THEN
            RETURN FALSE;
        END IF;
        IF p_schedule_end_date IS NOT NULL AND v_now > p_schedule_end_date THEN
            RETURN FALSE;
        END IF;

        -- Check time range if specified
        IF p_schedule_start_time IS NOT NULL AND p_schedule_end_time IS NOT NULL THEN
            v_current_time := TO_CHAR(v_now, 'HH24:MI');
            IF v_current_time < p_schedule_start_time OR v_current_time > p_schedule_end_time THEN
                RETURN FALSE;
            END IF;
        END IF;

        RETURN TRUE;
    END IF;

    -- If specific_days, check current day and time
    IF p_schedule_type = 'specific_days' THEN
        v_current_day := LOWER(TO_CHAR(v_now, 'Day'));
        v_current_day := TRIM(v_current_day); -- Remove trailing spaces
        v_current_time := TO_CHAR(v_now, 'HH24:MI');

        -- Loop through schedule_days to find matching day
        FOR v_day_schedule IN SELECT * FROM jsonb_array_elements(p_schedule_days)
        LOOP
            IF (v_day_schedule->>'day') = v_current_day THEN
                -- Day matches, check if all day or time-specific
                IF (v_day_schedule->>'allDay')::BOOLEAN THEN
                    RETURN TRUE;
                ELSE
                    -- Check time range
                    IF v_current_time >= (v_day_schedule->>'startTime') 
                       AND v_current_time <= (v_day_schedule->>'endTime') THEN
                        RETURN TRUE;
                    END IF;
                END IF;
            END IF;
        END LOOP;

        RETURN FALSE;
    END IF;

    -- Default: return is_active value
    RETURN p_is_active;
END;
$$ LANGUAGE plpgsql STABLE;

-- Example query to get currently active deals:
-- SELECT * FROM trusted_partner_discounts 
-- WHERE is_deal_active_now(
--     is_active, 
--     schedule_type, 
--     schedule_days, 
--     schedule_start_date, 
--     schedule_end_date, 
--     schedule_start_time, 
--     schedule_end_time
-- ) = TRUE;
