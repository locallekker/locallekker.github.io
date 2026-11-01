-- Migration: Fix role-resolution RLS recursion (42P17) on profiles + memberships
-- Date: 2026-06-28
-- Issue:
--   getUserRole() falls back to direct memberships/profiles SELECTs which can
--   hit "infinite recursion detected in policy" (Postgres 42P17). The app sees
--   this as recurring HTTP 403s during boot/role checks. Root cause is admin
--   RLS policies that self-reference their own table (e.g. an admin policy ON
--   profiles that does `EXISTS (SELECT 1 FROM profiles WHERE role='admin')`),
--   or cross-reference the other RLS-protected table, creating a cycle.
--
-- Strategy:
--   PART A (critical, non-destructive): ensure SECURITY DEFINER helper functions
--     exist. `get_my_role()` is the app's FIRST-CHOICE role source — when it
--     works the app never reaches the recursive direct queries. `is_admin()`
--     lets policies check admin status WITHOUT querying an RLS-protected table.
--   PART B (recursion-safe policies): drop the self-referential admin policies
--     and recreate them using `is_admin()` so no policy reads its own/another
--     RLS-protected table.
--
-- Safe to run multiple times (idempotent).

BEGIN;

-- =====================================================================
-- PART A: SECURITY DEFINER helper functions (non-destructive)
-- =====================================================================

-- get_my_role(): returns the current user's role, bypassing RLS. Reads
-- memberships first (authoritative for elevated roles), then profiles.
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (SELECT m.role FROM public.memberships m WHERE m.user_id = auth.uid() LIMIT 1),
    (SELECT p.role  FROM public.profiles   p WHERE p.id      = auth.uid() LIMIT 1)
  );
$$;

-- is_admin(): true when the current user resolves to the 'admin' role.
-- SECURITY DEFINER so policies can call it without recursively triggering
-- RLS on profiles/memberships.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.memberships m
    WHERE m.user_id = auth.uid() AND lower(m.role) = 'admin'
  ) OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND lower(p.role) = 'admin'
  );
$$;

GRANT EXECUTE ON FUNCTION public.get_my_role() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.is_admin()    TO authenticated, anon;

-- =====================================================================
-- PART B: Recursion-safe admin policies (uses is_admin(), never self-reads)
-- =====================================================================

-- ---- profiles ----
-- Drop the common self-referential admin policy names that cause recursion.
DROP POLICY IF EXISTS "Admins can view all profiles"   ON public.profiles;
DROP POLICY IF EXISTS "Admins can update all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Admins can insert profiles"     ON public.profiles;
DROP POLICY IF EXISTS "Admins can delete profiles"     ON public.profiles;
DROP POLICY IF EXISTS "Admin full access to profiles"  ON public.profiles;

CREATE POLICY "Admins can view all profiles" ON public.profiles
    FOR SELECT USING (public.is_admin());

CREATE POLICY "Admins can update all profiles" ON public.profiles
    FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY "Admins can insert profiles" ON public.profiles
    FOR INSERT WITH CHECK (public.is_admin());

CREATE POLICY "Admins can delete profiles" ON public.profiles
    FOR DELETE USING (public.is_admin());

-- ---- memberships ----
-- Drop admin policies that reference profiles/memberships (recursion source).
DROP POLICY IF EXISTS "Admins can view all memberships"   ON public.memberships;
DROP POLICY IF EXISTS "Admins can insert any membership"  ON public.memberships;
DROP POLICY IF EXISTS "Admins can update any membership"  ON public.memberships;
DROP POLICY IF EXISTS "Admins can delete any membership"  ON public.memberships;
DROP POLICY IF EXISTS "Admin can view all memberships"    ON public.memberships;
DROP POLICY IF EXISTS "Admin full access to memberships"  ON public.memberships;

CREATE POLICY "Admins can view all memberships" ON public.memberships
    FOR SELECT USING (public.is_admin());

CREATE POLICY "Admins can insert any membership" ON public.memberships
    FOR INSERT WITH CHECK (public.is_admin());

CREATE POLICY "Admins can update any membership" ON public.memberships
    FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY "Admins can delete any membership" ON public.memberships
    FOR DELETE USING (public.is_admin());

COMMIT;

-- =====================================================================
-- Verification (run manually after applying)
-- =====================================================================
-- SELECT public.get_my_role();           -- should return your role, no error
-- SELECT public.is_admin();              -- true/false, no recursion error
-- SELECT polname, cmd FROM pg_policies WHERE tablename IN ('profiles','memberships');
