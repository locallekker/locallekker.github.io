-- Enable admin uploads to partner-logos storage bucket
-- Context: Admin needs to upload trusted partner logo images
-- Table: storage.objects (RLS enabled)
-- Bucket: partner-logos

-- Safety: Only users resolved as admin by role lookup may insert/update/delete
-- Read remains open to all authenticated users (or per existing policy)

-- Preconditions: RLS must be enabled on storage.objects; bucket 'partner-logos' exists
-- This migration creates policies scoped by bucket_id and admin role determination.

begin;

-- Helper: role resolution aligned with app logic
-- The app determines role via profiles.role with fallbacks; here we rely
-- on profiles.role = 'admin' for simplicity and performance at the DB layer.
-- If you prefer the memberships/admin_dashboard checks, replace the EXISTS accordingly.

-- Policy: Allow admins to insert objects in partner-logos
create policy "admins can insert partner logos"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'partner-logos'
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
    )
  );

-- Policy: Allow admins to update objects they own in partner-logos
create policy "admins can update partner logos"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'partner-logos'
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
    )
  )
  with check (
    bucket_id = 'partner-logos'
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
    )
  );

-- Policy: Allow admins to delete objects in partner-logos
create policy "admins can delete partner logos"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'partner-logos'
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
    )
  );

commit;