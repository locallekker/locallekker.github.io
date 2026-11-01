// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

console.log("Creating user profile function...")

Deno.serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  const sql = `
-- Create a SECURITY DEFINER function to handle profile creation
-- This bypasses RLS policies and can be called by authenticated users

CREATE OR REPLACE FUNCTION public.create_user_profile(
  p_user_id UUID,
  p_user_data JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_type TEXT;
  role TEXT;
  profile_data JSONB;
BEGIN
  -- Get user type from metadata (this function runs with elevated privileges)
  SELECT COALESCE(raw_user_meta_data->>'user_type', 'member') INTO user_type
  FROM auth.users
  WHERE id = p_user_id;

  -- Determine role
  role := CASE WHEN user_type = 'trusted_partner' THEN 'trusted_partner' ELSE 'member' END;

  -- Build profile data
  profile_data := jsonb_build_object(
    'id', p_user_id,
    'email', p_user_data->>'email',
    'name', p_user_data->>'name',
    'surname', p_user_data->>'surname',
    'date_of_birth', CASE WHEN p_user_data->>'date_of_birth' IS NOT NULL THEN (p_user_data->>'date_of_birth')::timestamp with time zone ELSE NULL END,
    'gender', p_user_data->>'gender',
    'ethnicity', p_user_data->>'ethnicity',
    'province', p_user_data->>'province',
    'street', p_user_data->>'street',
    'suburb', p_user_data->>'suburb',
    'city', p_user_data->>'city',
    'contact', p_user_data->>'contact',
    'role', role,
    'subscription', CASE WHEN role = 'member' THEN 'pending' ELSE 'active' END
  );

  -- Remove null values
  profile_data := profile_data - (SELECT array_agg(k) FROM jsonb_object_keys(profile_data) k WHERE profile_data->k IS NULL);

  -- Upsert profile
  INSERT INTO public.profiles SELECT * FROM jsonb_to_record(profile_data) AS x(
    id UUID, email TEXT, name TEXT, surname TEXT, date_of_birth TIMESTAMP WITH TIME ZONE,
    gender TEXT, ethnicity TEXT, province TEXT, street TEXT, suburb TEXT,
    city TEXT, contact TEXT, role TEXT, subscription TEXT
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    name = EXCLUDED.name,
    surname = EXCLUDED.surname,
    date_of_birth = EXCLUDED.date_of_birth,
    gender = EXCLUDED.gender,
    ethnicity = EXCLUDED.ethnicity,
    province = EXCLUDED.province,
    street = EXCLUDED.street,
    suburb = EXCLUDED.suburb,
    city = EXCLUDED.city,
    contact = EXCLUDED.contact,
    role = EXCLUDED.role,
    subscription = EXCLUDED.subscription;

  -- Create membership record
  INSERT INTO public.memberships (user_id, role, gateway)
  VALUES (p_user_id, role, 'user_signup')
  ON CONFLICT (user_id) DO UPDATE SET
    role = EXCLUDED.role,
    gateway = EXCLUDED.gateway;

  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to create user profile: %', SQLERRM;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.create_user_profile(UUID, JSONB) TO authenticated;
  `

  try {
    const { data, error } = await supabase.rpc('exec_sql', { sql })

    if (error) {
      console.error('Error executing SQL:', error)
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      )
    }

    return new Response(
      JSON.stringify({ message: 'User profile function created successfully', data }),
      { headers: { "Content-Type": "application/json" } }
    )
  } catch (err) {
    console.error('Error:', err)
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    )
  }
})

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/create-profile-function' \
    --header 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0' \
    --header 'Content-Type: application/json' \
    --data '{"name":"Functions"}'

*/
