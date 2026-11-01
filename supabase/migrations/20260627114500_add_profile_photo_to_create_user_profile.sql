begin;

create or replace function public.create_user_profile(
  p_user_id uuid,
  p_user_data jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  user_type text;
  role text;
  v_dob_text text;
  v_dob timestamp with time zone;
  v_profile_photo_url text;
begin
  select coalesce(raw_user_meta_data->>'user_type', 'member') into user_type
  from auth.users
  where id = p_user_id;

  role := case when user_type = 'trusted_partner' then 'trusted_partner' else 'member' end;

  v_dob_text := nullif(btrim(coalesce(p_user_data->>'date_of_birth', '')), '');
  v_dob := null;
  v_profile_photo_url := nullif(btrim(coalesce(p_user_data->>'profile_photo_url', '')), '');

  if v_dob_text is not null then
    begin
      if v_dob_text ~ '^\d{4}-\d{2}-\d{2}$' then
        v_dob := (v_dob_text::date)::timestamp with time zone;
      else
        v_dob := v_dob_text::timestamp with time zone;
      end if;
    exception
      when others then
        v_dob := null;
    end;
  end if;

  insert into public.profiles (
    id,
    email,
    name,
    surname,
    date_of_birth,
    gender,
    ethnicity,
    province,
    street,
    suburb,
    city,
    contact,
    role,
    subscription,
    profile_photo_url
  )
  values (
    p_user_id,
    nullif(btrim(coalesce(p_user_data->>'email', '')), ''),
    nullif(btrim(coalesce(p_user_data->>'name', '')), ''),
    nullif(btrim(coalesce(p_user_data->>'surname', '')), ''),
    v_dob,
    nullif(btrim(coalesce(p_user_data->>'gender', '')), ''),
    nullif(btrim(coalesce(p_user_data->>'ethnicity', '')), ''),
    nullif(btrim(coalesce(p_user_data->>'province', '')), ''),
    nullif(btrim(coalesce(p_user_data->>'street', '')), ''),
    nullif(btrim(coalesce(p_user_data->>'suburb', '')), ''),
    nullif(btrim(coalesce(p_user_data->>'city', '')), ''),
    nullif(btrim(coalesce(p_user_data->>'contact', '')), ''),
    role,
    case when role = 'member' then 'pending' else 'active' end,
    v_profile_photo_url
  )
  on conflict (id) do update set
    email = coalesce(excluded.email, public.profiles.email),
    name = coalesce(excluded.name, public.profiles.name),
    surname = coalesce(excluded.surname, public.profiles.surname),
    date_of_birth = coalesce(excluded.date_of_birth, public.profiles.date_of_birth),
    gender = coalesce(excluded.gender, public.profiles.gender),
    ethnicity = coalesce(excluded.ethnicity, public.profiles.ethnicity),
    province = coalesce(excluded.province, public.profiles.province),
    street = coalesce(excluded.street, public.profiles.street),
    suburb = coalesce(excluded.suburb, public.profiles.suburb),
    city = coalesce(excluded.city, public.profiles.city),
    contact = coalesce(excluded.contact, public.profiles.contact),
    role = coalesce(excluded.role, public.profiles.role),
    subscription = coalesce(public.profiles.subscription, excluded.subscription),
    profile_photo_url = coalesce(excluded.profile_photo_url, public.profiles.profile_photo_url),
    updated_at = now();

  insert into public.memberships (user_id, role, gateway)
  values (p_user_id, role, 'user_signup')
  on conflict (user_id) do update set
    role = excluded.role,
    gateway = excluded.gateway,
    updated_at = now();

  return true;
exception
  when others then
    raise exception 'Failed to create user profile: %', sqlerrm;
end;
$$;

grant execute on function public.create_user_profile(uuid, jsonb) to authenticated;

commit;