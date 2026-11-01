-- Temporary fix: Grant service_role permissions to triggers
-- This allows triggers to bypass RLS during user creation

-- Grant bypass permissions to the postgres/service role for signup
GRANT ALL ON profiles TO service_role;
GRANT ALL ON memberships TO service_role;
GRANT ALL ON subscriptions TO service_role;

-- Ensure the trigger function has SECURITY DEFINER 
-- (runs with creator's permissions, not invoker's)

-- Check current trigger function for handle_new_user or similar
SELECT 
  p.proname as function_name,
  pg_get_functiondef(p.oid) as definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname LIKE '%user%'
  AND p.proname LIKE '%handle%'
ORDER BY p.proname;

-- If you find the trigger function name, we may need to recreate it with SECURITY DEFINER
-- Example (replace 'handle_new_user' with actual function name):
-- DROP FUNCTION IF EXISTS handle_new_user() CASCADE;
-- Then recreate it with SECURITY DEFINER clause
