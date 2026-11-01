-- Deep investigation: Why is INSERT still blocked with correct policies?
-- Hypothesis: There might be something wrong with how PostgREST handles the request

-- 1. Check if there are ANY other policies we missed (including system-level)
SELECT 
    n.nspname as schema,
    c.relname as table_name,
    pol.polname as policy_name,
    CASE pol.polcmd
        WHEN 'r' THEN 'SELECT'
        WHEN 'a' THEN 'INSERT'
        WHEN 'w' THEN 'UPDATE'
        WHEN 'd' THEN 'DELETE'
        WHEN '*' THEN 'ALL'
    END as command,
    CASE pol.polpermissive
        WHEN TRUE THEN 'PERMISSIVE'
        WHEN FALSE THEN 'RESTRICTIVE'
    END as permissive_type,
    r.rolname as role_name,
    pg_get_expr(pol.polqual, pol.polrelid) as using_expression,
    pg_get_expr(pol.polwithcheck, pol.polrelid) as with_check_expression
FROM pg_policy pol
JOIN pg_class c ON pol.polrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
LEFT JOIN pg_roles r ON r.oid = ANY(pol.polroles)
WHERE c.relname = 'notifications'
ORDER BY pol.polname;

-- 2. Check foreign key constraints on notifications table
SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_name = 'notifications';

-- 3. Try a test INSERT using SQL to see if it works
-- This will use the postgres role, bypassing RLS to test the table itself
INSERT INTO notifications (user_id, title, message, type, is_read, data)
VALUES (
    '6c815ef9-5e8a-498b-927c-9d807421f791',  -- Your user ID from logs
    'Test Notification',
    'Testing RLS',
    'deal_authorization_request',
    false,
    '{}'::jsonb
)
RETURNING id, user_id, created_at;

-- 4. Check if the issue is with the GRANT
SHOW row_security;

-- 5. Final check: Maybe we need to bypass RLS for service role
-- Check current role settings
SELECT current_user, current_role, session_user;
