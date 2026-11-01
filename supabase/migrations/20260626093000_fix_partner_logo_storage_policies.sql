-- Ensure trusted partners can upload/update/delete their own logos in partner-logos bucket
-- and anyone authenticated can view partner logos.

begin;

insert into storage.buckets (id, name, public)
values ('partner-logos', 'partner-logos', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "Trusted partners can upload their logos" on storage.objects;
drop policy if exists "Trusted partners can update their logos" on storage.objects;
drop policy if exists "Trusted partners can delete their logos" on storage.objects;
drop policy if exists "Anyone can view partner logos" on storage.objects;
drop policy if exists "Authenticated users can view partner logos" on storage.objects;

create policy "Trusted partners can upload their logos"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'partner-logos'
  and auth.uid()::text = (storage.foldername(name))[1]
  and exists (
    select 1
    from public.businesses b
    where b.owner_member_id = auth.uid()
  )
);

create policy "Trusted partners can update their logos"
on storage.objects for update
to authenticated
using (
  bucket_id = 'partner-logos'
  and auth.uid()::text = (storage.foldername(name))[1]
  and exists (
    select 1
    from public.businesses b
    where b.owner_member_id = auth.uid()
  )
)
with check (
  bucket_id = 'partner-logos'
  and auth.uid()::text = (storage.foldername(name))[1]
  and exists (
    select 1
    from public.businesses b
    where b.owner_member_id = auth.uid()
  )
);

create policy "Trusted partners can delete their logos"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'partner-logos'
  and auth.uid()::text = (storage.foldername(name))[1]
  and exists (
    select 1
    from public.businesses b
    where b.owner_member_id = auth.uid()
  )
);

create policy "Authenticated users can view partner logos"
on storage.objects for select
to authenticated
using (bucket_id = 'partner-logos');

commit;
