-- Migration: Prevent duplicate profiles by email
-- This migration removes duplicate profiles based on email, keeping the most recent one,
-- and adds a unique constraint on email to prevent future duplicates

begin;

-- Step 1: Identify and remove duplicate profiles, keeping the most recent one per email
-- Use a CTE to find duplicates and delete all but the most recent
with duplicates as (
  select id, email, created_at,
         row_number() over (partition by email order by created_at desc) as rn
  from public.profiles
  where email is not null and email != ''
)
delete from public.profiles
where id in (
  select id from duplicates where rn > 1
);

-- Step 2: Add unique constraint on email (excluding nulls)
-- First, ensure no null emails violate the constraint
update public.profiles
set email = null
where email = '';

-- Add the unique index (allows nulls)
create unique index if not exists idx_profiles_email_unique
on public.profiles (email)
where email is not null;

commit;