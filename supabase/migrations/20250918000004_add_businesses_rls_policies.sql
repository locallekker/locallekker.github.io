-- Add RLS policies for businesses table
-- This ensures users can only access their own business records

begin;

-- Enable RLS on businesses table
alter table public.businesses enable row level security;

-- Allow users to select their own business
create policy "Users can view their own business" on public.businesses
  for select using (auth.uid() = owner_member_id);

-- Allow users to insert their own business
create policy "Users can insert their own business" on public.businesses
  for insert with check (auth.uid() = owner_member_id);

-- Allow users to update their own business
create policy "Users can update their own business" on public.businesses
  for update using (auth.uid() = owner_member_id) with check (auth.uid() = owner_member_id);

-- Allow users to delete their own business
create policy "Users can delete their own business" on public.businesses
  for delete using (auth.uid() = owner_member_id);

-- Allow service role full access (for admin operations)
create policy "Service role can manage all businesses" on public.businesses
  for all using (auth.jwt() ->> 'role' = 'service_role');

commit;