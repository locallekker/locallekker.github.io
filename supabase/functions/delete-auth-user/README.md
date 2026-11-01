PDelete Auth User - Supabase Edge Function

What this function does
- Accepts POST requests with JSON body { "user_id": "<uuid>" }.
- Requires Authorization header: Bearer <admin_access_token> (the admin's access token).
- Verifies the caller is an admin by checking `admin_dashboard` table.
- Uses the Supabase `service_role` key (from environment variable `SUPABASE_SERVICE_ROLE_KEY`) to call the Auth admin endpoint and delete the specified `auth.users` entry.

Security: keep `SUPABASE_SERVICE_ROLE_KEY` secret and only set it in the project secrets/vars for the function.

Deploy (recommended: Supabase CLI)
1) Install Supabase CLI: https://supabase.com/docs/guides/cli

2) Link to your project

```pwsh
supabase login
supabase link --project-ref your-project-ref
```

3) Save secrets (service role key and optional SUPABASE_URL)

```pwsh
supabase secrets set SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"
supabase secrets set SUPABASE_URL="https://your-project-ref.supabase.co"
```

4) Deploy the function

```pwsh
# from repository root, where the `supabase/functions/delete-auth-user` folder exists
supabase functions deploy delete-auth-user
```

5) Test with curl (example)

```bash
curl -X POST 'https://<project>.functions.supabase.co/delete-auth-user' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <ADMIN_ACCESS_TOKEN>' \
  -d '{"user_id":"e31e37fa-1cdc-4acd-adc2-2d623a92cb74"}'
```

Notes
- This function assumes there is an `admin_dashboard` table that holds `admin_user_id` values to authorize admin callers (this mirrors your app). Adjust the REST path if your admin table or column names differ.
- The function calls the Supabase Auth admin REST endpoint to remove users; this requires the service role key.
- Log and audit calls on your server if you want full traceability.

Next steps for your app
- Update `AdminService` in the Flutter app to POST to this function instead of calling `supabase.auth.admin.deleteUser` from the client.
- Keep the delete-data RPC (`admin_delete_trusted_partner_data`) in your DB and call it first from the client; after it returns success call this function to remove the `auth.users` row.
