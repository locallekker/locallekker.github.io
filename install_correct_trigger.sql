
-- Install the correct trigger on auth.users table
-- This will ensure our handle_new_user_role_assignment function runs when users are created

BEGIN;

-- Drop any existing trigger that might conflict
DROP TRIGGER IF EXISTS create_profile_after_user_insert ON auth.users;
DROP TRIGGER IF EXISTS handle_new_user_role_assignment_trigger ON auth.users;

-- Create the trigger using our function
CREATE TRIGGER handle_new_user_role_assignment_trigger
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_role_assignment();

COMMIT;

-- Verify the trigger was created
SELECT 
    trigger_name,
    event_manipulation,
    event_object_schema,
    event_object_table,
    action_statement,
    action_timing
FROM information_schema.triggers 
WHERE event_object_table = 'users' 
AND event_object_schema = 'auth'
AND trigger_name = 'handle_new_user_role_assignment_trigger';

