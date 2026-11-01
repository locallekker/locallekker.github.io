-- Migration: Create base tables for role management system
-- This creates the essential tables needed before other migrations can run

begin;

-- Create profiles table
create table if not exists public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  name text,
  surname text,
  email text,
  role text default 'user',
  category text,
  street text,
  suburb text,
  city text,
  province text,
  contact text,
  gender text,
  ethnicity text,
  date_of_birth date,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Create memberships table
create table if not exists public.memberships (
  user_id uuid references auth.users(id) on delete cascade,
  role text not null,
  gateway text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  primary key (user_id)
);

-- Create trusted_partners table
create table if not exists public.trusted_partners (
  user_id uuid references auth.users(id) on delete cascade primary key,
  business_name text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Create businesses table
create table if not exists public.businesses (
  id uuid default gen_random_uuid() primary key,
  owner_member_id uuid references auth.users(id) on delete cascade,
  name text,
  category text,
  address text,
  latitude double precision,
  longitude double precision,
  contact_email text,
  contact_number text,
  verified boolean default false,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  unique(owner_member_id)
);

-- Create users table (for backward compatibility)
create table if not exists public.users (
  id uuid references auth.users(id) on delete cascade primary key,
  email text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS
alter table public.profiles enable row level security;
alter table public.memberships enable row level security;
alter table public.trusted_partners enable row level security;
alter table public.businesses enable row level security;
alter table public.users enable row level security;

-- Create basic policies
create policy "Users can view own profile" on public.profiles
  for select using (auth.uid() = id);

create policy "Users can update own profile" on public.profiles
  for update using (auth.uid() = id);

create policy "Users can view own membership" on public.memberships
  for select using (auth.uid() = user_id);

create policy "Users can view own trusted_partner record" on public.trusted_partners
  for select using (auth.uid() = user_id);

create policy "Users can view own business" on public.businesses
  for select using (auth.uid() = owner_member_id);

create policy "Users can update own business" on public.businesses
  for update using (auth.uid() = owner_member_id);

create policy "Users can view own user record" on public.users
  for select using (auth.uid() = id);

-- Create indexes for performance
create index if not exists idx_profiles_role on public.profiles(role);
create index if not exists idx_memberships_role on public.memberships(role);
create index if not exists idx_memberships_user_id on public.memberships(user_id);
create index if not exists idx_businesses_owner_member_id on public.businesses(owner_member_id);

commit;