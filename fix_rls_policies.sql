-- Fix RLS Policies for Member Signup
-- This script fixes the infinite recursion issue in RLS policies

-- Drop ALL existing policies on profiles and memberships tables
DO $$
DECLARE
    policy_record RECORD;
BEGIN
    -- Drop all policies on profiles table
    FOR policy_record IN
        SELECT schemaname, tablename, policyname
        FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'profiles'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I',
                      policy_record.policyname, policy_record.schemaname, policy_record.tablename);
    END LOOP;

    -- Drop all policies on memberships table
    FOR policy_record IN
        SELECT schemaname, tablename, policyname
        FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'memberships'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I',
                      policy_record.policyname, policy_record.schemaname, policy_record.tablename);
    END LOOP;
END $$;

-- Create simple, non-recursive policies for profiles
CREATE POLICY "profiles_select_policy" ON public.profiles
FOR SELECT USING (auth.uid() = id);

CREATE POLICY "profiles_insert_policy" ON public.profiles
FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_policy" ON public.profiles
FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- Create simple, non-recursive policies for memberships
CREATE POLICY "memberships_select_policy" ON public.memberships
FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "memberships_insert_policy" ON public.memberships
FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "memberships_update_policy" ON public.memberships
FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Allow admin access (by email for now - can be changed to role-based later)
CREATE POLICY "admin_profiles_access" ON public.profiles
FOR ALL USING (auth.jwt() ->> 'email' IN ('admin@locallekker.com', 'clydemflan@gmail.com'));

CREATE POLICY "admin_memberships_access" ON public.memberships
FOR ALL USING (auth.jwt() ->> 'email' IN ('admin@locallekker.com', 'clydemflan@gmail.com'));