-- ============================================================
-- CLEANUP: Remove duplicate/dangerous subscription policies
-- Run this in Supabase SQL Editor NOW
-- ============================================================

-- Drop ALL old INSERT policies (the names from the actual database)
DROP POLICY IF EXISTS "Authenticated members can insert subscriptions" ON subscriptions;
DROP POLICY IF EXISTS "Users can insert their own subscriptions" ON subscriptions;
-- Our new one stays:
-- "members_insert_own_subscriptions" WITH CHECK (user_id = auth.uid())

-- Clean up duplicate SELECT policies (keep only one)
DROP POLICY IF EXISTS "Users can view their own subscriptions" ON subscriptions;
-- Keeps: "Members can view their own subscriptions" + "Admins can view all subscriptions"

-- Clean up duplicate UPDATE policies (keep only one)
DROP POLICY IF EXISTS "Users can update their own subscriptions" ON subscriptions;
-- Keeps: "Members can update their own subscriptions"

-- ============================================================
-- VERIFY: Run this after to confirm clean state
-- ============================================================
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies 
WHERE tablename = 'subscriptions'
ORDER BY cmd, policyname;

-- Expected result:
-- INSERT: members_insert_own_subscriptions (user_id = auth.uid())
-- SELECT: Admins can view all subscriptions
-- SELECT: Members can view their own subscriptions (user_id = auth.uid())
-- UPDATE: Members can update their own subscriptions (user_id = auth.uid())
