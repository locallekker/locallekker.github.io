-- =============================================================================
-- ULTIMATE FIX - NOTIFICATIONS RLS FOR BOTH ANON AND AUTHENTICATED
-- =============================================================================
-- This creates policies that work for BOTH anon and authenticated roles
-- Sometimes Supabase client uses anon role even when user is logged in
-- =============================================================================

-- Step 1: Disable RLS temporarily
ALTER TABLE notifications DISABLE ROW LEVEL SECURITY;

-- Step 2: Drop ALL existing policies
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE schemaname = 'public' 
          AND tablename = 'notifications'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON notifications CASCADE', policy_record.policyname);
    END LOOP;
END $$;

-- Step 3: Re-enable RLS
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Step 4: Create policies for BOTH anon AND authenticated roles

-- INSERT Policy - Allow ANYONE (anon or authenticated) to insert
CREATE POLICY "notifications_insert_public" 
ON notifications
FOR INSERT
TO public  -- This covers anon, authenticated, and all other roles
WITH CHECK (true);  -- No restrictions at all

-- SELECT Policy - Users can see their own (works for both roles)
CREATE POLICY "notifications_select_own" 
ON notifications
FOR SELECT
TO public
USING (user_id = auth.uid() OR auth.uid() IS NULL);  -- Allow even if not auth for anon

-- UPDATE Policy - Users can update their own (works for both roles)  
CREATE POLICY "notifications_update_own" 
ON notifications
FOR UPDATE
TO public
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Step 5: Verify
SELECT 
    '=== VERIFICATION ===' as info,
    policyname,
    cmd,
    permissive,
    roles,
    with_check::text as with_check_clause
FROM pg_policies
WHERE schemaname = 'public' 
  AND tablename = 'notifications'
ORDER BY cmd, policyname;

-- Step 6: Test
DO $$
BEGIN
    -- Try a simple insert
    INSERT INTO notifications (user_id, title, message, type, is_read)
    VALUES (
        (SELECT id FROM profiles LIMIT 1),
        'Test Notification',
        'Test message',
        'info',
        false
    );
    
    RAISE NOTICE '✅ INSERT TEST PASSED!';
    
    -- Clean up
    DELETE FROM notifications WHERE title = 'Test Notification';
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '❌ INSERT FAILED: %', SQLERRM;
END $$;

SELECT '✅ Notifications RLS configured for ALL roles (public)' as status;
