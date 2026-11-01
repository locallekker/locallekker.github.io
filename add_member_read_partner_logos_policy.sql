-- Enable members to view partner logos
-- Context: Members need to see trusted partner logo images when browsing deals
-- Table: storage.objects (RLS enabled)
-- Bucket: partner-logos

-- This policy allows all authenticated users (members) to SELECT/read from partner-logos bucket
-- Works alongside existing admin write policies

begin;

-- Drop existing "Anyone can view partner logos" policy if it exists (may have been removed)
drop policy if exists "Anyone can view partner logos" on storage.objects;

-- Create new policy allowing all authenticated users to view partner logos
create policy "Authenticated users can view partner logos"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'partner-logos');

commit;
