-- Add contact_number column to businesses table
-- This migration ensures the contact_number column exists

begin;

-- Add contact_number column to businesses table if it doesn't exist
alter table public.businesses
add column if not exists contact_number text;

-- Add comment for documentation
comment on column public.businesses.contact_number is 'Business contact phone number';

commit;