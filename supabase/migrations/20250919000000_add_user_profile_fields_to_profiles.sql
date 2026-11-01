-- Migration: Add user profile fields to profiles table
-- This migration adds the missing columns needed for user profiles

begin;

-- Add user-specific columns to profiles table
alter table public.profiles
add column if not exists street text,
add column if not exists suburb text,
add column if not exists city text,
add column if not exists contact text,
add column if not exists gender text,
add column if not exists ethnicity text,
add column if not exists province text,
add column if not exists date_of_birth timestamp with time zone;

-- Add comments for documentation
comment on column public.profiles.street is 'User street address';
comment on column public.profiles.suburb is 'User suburb';
comment on column public.profiles.city is 'User city';
comment on column public.profiles.contact is 'User contact phone number';
comment on column public.profiles.gender is 'User gender (Male/Female/Other)';
comment on column public.profiles.ethnicity is 'User ethnicity';
comment on column public.profiles.province is 'User province';
comment on column public.profiles.date_of_birth is 'User date of birth';

commit;