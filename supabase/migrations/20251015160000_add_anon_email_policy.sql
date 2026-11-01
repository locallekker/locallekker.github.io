-- Migration: Add anon policy for email checking
-- +migrate Up

CREATE POLICY "Anon can check email" ON public.profiles
FOR SELECT USING (auth.jwt() IS NULL);

-- +migrate Down

DROP POLICY IF EXISTS "Anon can check email" ON public.profiles;