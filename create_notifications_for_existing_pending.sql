-- Create notifications for existing pending deal authorizations that don't have notifications
INSERT INTO notifications (user_id, title, message, type, data, is_read, created_at)
SELECT
    da.trusted_partner_user_id,
    'New Deal Authorization Request',
    'A member has requested authorization for a deal worth R' || da.amount::text,
    'deal_request',
    json_build_object('deal_authorization_id', da.id, 'member_id', da.member_id, 'amount', da.amount),
    false,
    da.created_at
FROM deal_authorizations da
LEFT JOIN notifications n ON n.data->>'deal_authorization_id' = da.id::text
WHERE da.status = 'pending'
AND n.id IS NULL;

-- Verify the notifications were created
SELECT
    da.id as deal_auth_id,
    da.status,
    da.created_at as deal_created,
    n.id as notification_id,
    n.title,
    n.created_at as notification_created
FROM deal_authorizations da
LEFT JOIN notifications n ON n.data->>'deal_authorization_id' = da.id::text
WHERE da.status = 'pending'
ORDER BY da.created_at DESC;