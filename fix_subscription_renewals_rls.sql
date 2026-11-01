-- =============================================================================
-- FIX: Add INSERT policy for subscription_renewals table
-- =============================================================================
-- Issue: Users cannot insert into subscription_renewals due to missing RLS policy
-- Solution: Add policy allowing users to insert their own renewal records
-- =============================================================================

-- Drop existing policies if they exist (to ensure clean state)
DROP POLICY IF EXISTS "Users can view their own renewal history" ON public.subscription_renewals;
DROP POLICY IF EXISTS "Service role can manage renewals" ON public.subscription_renewals;
DROP POLICY IF EXISTS "Users can insert their own renewal records" ON public.subscription_renewals;

-- Policy 1: Users can view their own renewal history
CREATE POLICY "Users can view their own renewal history" ON public.subscription_renewals
    FOR SELECT 
    USING (auth.uid() = user_id);

-- Policy 2: Users can insert their own renewal records
CREATE POLICY "Users can insert their own renewal records" ON public.subscription_renewals
    FOR INSERT 
    WITH CHECK (auth.uid() = user_id);

-- Policy 3: Service role can manage all renewals
CREATE POLICY "Service role can manage renewals" ON public.subscription_renewals
    FOR ALL 
    USING (auth.jwt() ->> 'role' = 'service_role');

-- Verify RLS is enabled
ALTER TABLE public.subscription_renewals ENABLE ROW LEVEL SECURITY;

-- Verification query (run this to check policies are created)
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'subscription_renewals'
ORDER BY policyname;
