-- UPDATED: Create a SECURITY DEFINER function that returns the full notification
-- This avoids the SELECT RLS issue by returning data directly from the function

-- Drop the old function
DROP FUNCTION IF EXISTS public.create_notification_bypass_rls(UUID, TEXT, TEXT, TEXT, JSONB);

-- Create updated function that returns the full notification record
CREATE OR REPLACE FUNCTION public.create_notification_bypass_rls(
    p_user_id UUID,
    p_title TEXT,
    p_message TEXT,
    p_type TEXT,
    p_data JSONB DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    title TEXT,
    message TEXT,
    type TEXT,
    data JSONB,
    is_read BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER  -- This is the key - function runs as owner, bypassing RLS
AS $$
BEGIN
    -- Insert the notification and return the full record
    RETURN QUERY
    INSERT INTO public.notifications (user_id, title, message, type, data, is_read)
    VALUES (p_user_id, p_title, p_message, p_type, COALESCE(p_data, '{}'::jsonb), false)
    RETURNING 
        notifications.id,
        notifications.user_id,
        notifications.title,
        notifications.message,
        notifications.type,
        notifications.data,
        notifications.is_read,
        notifications.created_at,
        notifications.updated_at;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.create_notification_bypass_rls TO authenticated;

-- Test the function
SELECT * FROM public.create_notification_bypass_rls(
    '6c815ef9-5e8a-498b-927c-9d807421f791'::uuid,
    'Test Notification v2',
    'Testing updated bypass function that returns full record',
    'test',
    '{"test": true}'::jsonb
);
