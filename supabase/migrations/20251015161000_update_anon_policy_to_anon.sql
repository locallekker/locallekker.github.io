-- Migration: Update anon policy for email checking
-- +migrate Up

DROP POLICY IF EXISTS "Anon can check email" ON public.profiles;

CREATE POLICY "Anon can check email" ON public.profiles
FOR SELECT TO anon USING (true);

-- +migrate Down

DROP POLICY IF EXISTS "Anon can check email" ON public.profiles;