create function public.get_admin_dashboard()
returns json
language plpgsql
as $$
declare
  result json;
begin
  select json_build_object(
    'total_users', (select count(*) from users),
    'total_merchants', (select count(*) from profiles where role = 'merchant'),
    'total_online_purchases', coalesce((select sum(amount) from payments where in_store = false and payment_status = 'complete'), 0),
    'total_in_store_purchases', coalesce((select sum(amount) from payments where in_store = true and payment_status = 'complete'), 0)
  ) into result;

  return result;
end;
$$;