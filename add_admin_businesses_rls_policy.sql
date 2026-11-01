-- Add admin policy to allow admins to UPDATE all businesses (including logo_url)

BEGIN;

-- Create policy allowing admins to manage all businesses
-- This checks the profiles table for role='admin'
CREATE POLICY "Admins can manage all businesses" 
ON public.businesses
FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid() 
        AND profiles.role = 'admin'
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid() 
        AND profiles.role = 'admin'
    )
);

COMMIT;

-- Verify the new policy was created
SELECT 
    policyname,
    cmd,
    qual::text as using_expression
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'businesses'
  AND policyname = 'Admins can manage all businesses';

-- Test: Admin should now be able to see and update That Old Oak
SELECT 
    'Admin policy test' as test,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_policies
            WHERE schemaname = 'public'
              AND tablename = 'businesses'
              AND policyname = 'Admins can manage all businesses'
        ) THEN '✅ Admin policy created successfully'
        ELSE '❌ Admin policy NOT found'
    END as status;
