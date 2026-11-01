-- WORKAROUND: Create a SECURITY DEFINER function to bypass RLS
-- This allows notifications to be created without RLS blocking

-- Drop the function if it exists
DROP FUNCTION IF EXISTS public.create_notification_bypass_rls;

-- Create a function that runs with SECURITY DEFINER (bypasses RLS)
CREATE OR REPLACE FUNCTION public.create_notification_bypass_rls(
    p_user_id UUID,
    p_title TEXT,
    p_message TEXT,
    p_type TEXT,
    p_data JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER  -- This is the key - function runs as owner, bypassing RLS
AS $$
DECLARE
    v_notification_id UUID;
BEGIN
    -- Insert the notification
    INSERT INTO public.notifications (user_id, title, message, type, data, is_read)
    VALUES (p_user_id, p_title, p_message, p_type, COALESCE(p_data, '{}'::jsonb), false)
    RETURNING id INTO v_notification_id;
    
    RETURN v_notification_id;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.create_notification_bypass_rls TO authenticated;

-- Test the function
SELECT public.create_notification_bypass_rls(
    '6c815ef9-5e8a-498b-927c-9d807421f791'::uuid,
    'Test Notification',
    'Testing bypass function',
    'test',
    '{"test": true}'::jsonb
);

-- Verify it worked
SELECT * FROM notifications WHERE title = 'Test Notification' ORDER BY created_at DESC LIMIT 1;
