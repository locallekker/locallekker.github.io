begin;

alter table public.profiles
add column if not exists profile_photo_url text;

insert into storage.buckets (id, name, public)
values ('member-profile-photos', 'member-profile-photos', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "Members can upload their own profile photos" on storage.objects;
drop policy if exists "Members can update their own profile photos" on storage.objects;
drop policy if exists "Members can delete their own profile photos" on storage.objects;
drop policy if exists "Authenticated users can view member profile photos" on storage.objects;

create policy "Members can upload their own profile photos"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'member-profile-photos'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "Members can update their own profile photos"
on storage.objects for update
to authenticated
using (
  bucket_id = 'member-profile-photos'
  and auth.uid()::text = (storage.foldername(name))[1]
)
with check (
  bucket_id = 'member-profile-photos'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "Members can delete their own profile photos"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'member-profile-photos'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "Authenticated users can view member profile photos"
on storage.objects for select
to authenticated
using (bucket_id = 'member-profile-photos');

commit;