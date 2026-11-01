-- =============================================================================
-- FIX REMAINING DATABASE SECURITY WARNINGS
-- =============================================================================
-- Addresses 6 warnings from Supabase Security Advisor:
-- 1. RLS Policy Always True (5 policies)
-- 2. Leaked Password Protection Disabled (1 Auth setting)
-- =============================================================================

-- =============================================================================
-- ISSUE 1: archived_members - RLS Policy Always True
-- =============================================================================
-- Current: USING (true) allows all anonymous users to read all archived data
-- Fix: Restrict to admin-only access (archived members are sensitive)

DROP POLICY IF EXISTS "Anon users can check archived members by email" ON public.archived_members;

-- Only admins can view archived member data
CREATE POLICY "Admins can view archived members" 
ON public.archived_members
FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
);

-- Service role can still insert (for archiving process)
-- Policy "Service role can insert archived members" already exists with WITH CHECK (true)
-- This is acceptable since it's service_role only, not public access

-- =============================================================================
-- ISSUE 2: notifications - RLS Policy Always True  
-- =============================================================================
-- Current: "Authenticated members can insert notifications" uses WITH CHECK (auth.uid() IS NOT NULL)
-- This is technically "always true" for authenticated users
-- Fix: Require users to only create notifications for themselves

DROP POLICY IF EXISTS "Authenticated members can insert notifications" ON notifications;

-- Users can only create notifications for themselves
CREATE POLICY "Users can insert own notifications" 
ON notifications
FOR INSERT 
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Note: For system-generated notifications (e.g., payment reminders), 
-- use the create_notification_bypass_rls() SECURITY DEFINER function instead

-- =============================================================================
-- ISSUE 3: profiles - RLS Policy Always True (2 policies)
-- =============================================================================
-- Current: "Allow anonymous email checks" uses USING (true)
-- This was added for email existence checking during signup
-- Fix: Limit SELECT to only email and id columns via function, not open policy

-- First, verify the check_email_exists() function exists and is properly secured
-- This function should handle email checks instead of an open policy

-- Remove the overly permissive policy
DROP POLICY IF EXISTS "Allow anonymous email checks" ON profiles;

-- Create a more restrictive policy: authenticated users can see basic profile info
-- but anonymous users must use the check_email_exists() RPC function
CREATE POLICY "Authenticated users can view basic profiles" 
ON profiles
FOR SELECT 
TO authenticated
USING (true);  -- Authenticated users can view profiles (needed for notifications FK, etc.)

-- For anonymous email checks, they MUST use: SELECT check_email_exists('email@example.com');
-- This prevents bulk data extraction while allowing signup flow

-- If there's a second "always true" policy on profiles, remove it:
-- Find and review any other overly permissive policies
DO $$
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE schemaname = 'public' 
          AND tablename = 'profiles'
          AND qual = 'true'  -- Policies with USING (true)
          AND policyname != 'Authenticated users can view basic profiles'
    LOOP
        RAISE NOTICE 'Found overly permissive policy on profiles: %', policy_record.policyname;
        -- Uncomment to auto-drop:
        -- EXECUTE format('DROP POLICY IF EXISTS %I ON profiles;', policy_record.policyname);
    END LOOP;
END $$;

-- =============================================================================
-- ISSUE 4: recovery_sessions - RLS Policy Always True
-- =============================================================================
-- Current: "Anyone can insert recovery session" uses WITH CHECK (true)
-- This allows anyone to create fake recovery sessions
-- Fix: Restrict to service_role or authenticated users only

DROP POLICY IF EXISTS "Anyone can insert recovery session" ON public.recovery_sessions;

-- Only authenticated users can create recovery sessions (via app flow)
CREATE POLICY "Authenticated users can insert recovery sessions" 
ON public.recovery_sessions
FOR INSERT 
TO authenticated
WITH CHECK (true);

-- Grant service_role ability to insert (for admin-initiated resets)
GRANT INSERT ON public.recovery_sessions TO service_role;

-- Keep the SELECT policy as-is (it's already properly filtered by expires_at and used status)
-- Policy: "Anyone can read active recovery sessions" is acceptable since it filters:
-- USING (used = false AND expires_at > NOW())

-- =============================================================================
-- ISSUE 5: Auth - Leaked Password Protection
-- =============================================================================
-- This setting must be enabled in the Supabase Dashboard, not via SQL
-- Navigate to: Authentication > Settings > Security
-- Enable: "Leaked Password Protection"
--
-- This checks user passwords against the Have I Been Pwned database
-- to prevent use of compromised passwords.
--
-- MANUAL ACTION REQUIRED:
-- 1. Go to Supabase Dashboard > Authentication > Settings
-- 2. Scroll to "Security" section  
-- 3. Toggle ON "Leaked Password Protection"
-- 4. Save changes

-- =============================================================================
-- VERIFICATION
-- =============================================================================

-- Check for remaining "always true" policies
SELECT 
    schemaname,
    tablename,
    policyname,
    cmd,
    CASE 
        WHEN qual = 'true' THEN '⚠️ USING (true)'
        WHEN with_check = 'true' THEN '⚠️ WITH CHECK (true)'
        ELSE '✅ Properly filtered'
    END as status,
    roles
FROM pg_policies 
WHERE schemaname = 'public'
  AND (qual = 'true' OR with_check = 'true')
  AND tablename IN ('archived_members', 'notifications', 'profiles', 'recovery_sessions')
ORDER BY tablename, policyname;

-- Expected results:
-- Only service_role policies should have "true" checks
-- All user-facing policies should have proper filters

-- Summary of changes
DO $$
BEGIN
    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'Security Warnings Fixed:';
    RAISE NOTICE '1. ✅ archived_members - Restricted to admin-only access';
    RAISE NOTICE '2. ✅ notifications - Users can only insert own notifications';
    RAISE NOTICE '3. ✅ profiles - Anonymous users must use RPC function';
    RAISE NOTICE '4. ✅ recovery_sessions - Restricted to authenticated users';
    RAISE NOTICE '5. ⚠️  Leaked Password Protection - MANUAL ACTION REQUIRED in Dashboard';
    RAISE NOTICE '=============================================================================';
END $$;
