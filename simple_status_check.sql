
-- Simple test: Use the same signup method as the Flutter app
-- This will test the full flow through Supabase Auth

-- First, let's check if we can use the Supabase RPC or if we need to use the client
-- Since we can't run the Flutter app here, let's check recent activity instead

SELECT 
    'Current Status Check:' as info,
    COUNT(*) as total_trusted_partners
FROM trusted_partners;

-- Check the most recent trusted partner creation
SELECT 
    'Most Recent Trusted Partner:' as info,
    tp.created_at,
    p.email,
    p.name,
    p.surname,
    p.role,
    p.admin_created,
    p.password_set,
    tp.business_name
FROM trusted_partners tp
JOIN profiles p ON tp.user_id = p.id
ORDER BY tp.created_at DESC
LIMIT 1;

-- Check if the trigger is still installed
SELECT 
    'Trigger Status:' as info,
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers 
WHERE event_object_table = 'users' 
AND event_object_schema = 'auth'
AND trigger_name = 'handle_new_user_role_assignment_trigger';

