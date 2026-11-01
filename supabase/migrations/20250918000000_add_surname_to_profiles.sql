-- Migration: Add surname column to profiles table
-- This migration adds a surname column to store the user's surname separately

begin;

-- Add surname column to profiles table
alter table public.profiles add column if not exists surname text;

-- Update existing profiles to extract surname from name if possible
-- This is a best-effort attempt to populate surname for existing users
update public.profiles
set surname = split_part(trim(name), ' ', -1)
where surname is null and name is not null and name != '';

commit;