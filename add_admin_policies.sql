-- Add admin policies to allow admin users to read all profiles and memberships

begin;

-- Clean up any malformed legacy policies
drop policy if exists "Admins can view all profiles" on public.profiles;
drop policy if exists "Admins can view all memberships" on public.memberships;

-- Allow admins (resolved via JWT email/claim) to read all profiles without self-recursion
create policy "Admins can view all profiles"
	on public.profiles
	for select
	using (
		coalesce(auth.jwt() ->> 'role', '') = 'admin'
		or coalesce(auth.jwt() ->> 'email', '') in (
			'admin@locallekker.com',
			'clydemflan@gmail.com',
			'locallekkerclub@gmail.com'
		)
	);

-- Allow admins to read all memberships without self-recursive checks
create policy "Admins can view all memberships"
	on public.memberships
	for select
	using (
		coalesce(auth.jwt() ->> 'role', '') = 'admin'
		or coalesce(auth.jwt() ->> 'email', '') in (
			'admin@locallekker.com',
			'clydemflan@gmail.com',
			'locallekkerclub@gmail.com'
		)
	);

commit;
