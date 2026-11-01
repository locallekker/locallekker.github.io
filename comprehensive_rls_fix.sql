-- Comprehensive RLS Policy Fix
-- This script completely resets RLS policies to avoid circular dependencies

-- Step 1: Drop ALL existing policies on both tables
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Admins can view all memberships" ON public.memberships;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own membership" ON public.memberships;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own membership" ON public.memberships;
DROP POLICY IF EXISTS "Users can update own membership" ON public.memberships;
DROP POLICY IF EXISTS "Enable read access for own profile" ON public.profiles;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.profiles;
DROP POLICY IF EXISTS "Enable update for users based on user_id" ON public.profiles;
DROP POLICY IF EXISTS "Enable read access for own membership" ON public.memberships;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.memberships;
DROP POLICY IF EXISTS "Enable update for users based on user_id" ON public.memberships;

-- Step 2: Create new policies that avoid circular dependencies

-- Profiles table policies
-- Admin users (by email) can do everything
CREATE POLICY "Admin full access to profiles" ON public.profiles
FOR ALL USING (auth.jwt() ->> 'email' = 'admin@locallekker.com');

-- Regular users can only see/update their own profile
CREATE POLICY "Users can view own profile" ON public.profiles
FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON public.profiles
FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.profiles
FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- Memberships table policies
-- Admin users (by email) can do everything
CREATE POLICY "Admin full access to memberships" ON public.memberships
FOR ALL USING (auth.jwt() ->> 'email' = 'admin@locallekker.com');

-- Regular users can only see/update their own membership
CREATE POLICY "Users can view own membership" ON public.memberships
FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own membership" ON public.memberships
FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own membership" ON public.memberships
FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);