-- =============================================================================
-- CREATE SUBSCRIPTIONS TABLE WITH RLS POLICIES
-- This creates ONLY the subscriptions table - safe to run on existing database
-- =============================================================================

-- Create subscriptions table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    plan_type TEXT NOT NULL,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'pending', 'cancelled', 'expired')),
    auto_renew BOOLEAN DEFAULT FALSE,
    current_period_start TIMESTAMP WITH TIME ZONE,
    current_period_end TIMESTAMP WITH TIME ZONE,
    next_payment_date TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on subscriptions table
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Members can view their own subscriptions" ON public.subscriptions;
DROP POLICY IF EXISTS "Members can update their own subscriptions" ON public.subscriptions;
DROP POLICY IF EXISTS "Authenticated members can insert subscriptions" ON public.subscriptions;
DROP POLICY IF EXISTS "Admins can view all subscriptions" ON public.subscriptions;

-- RLS Policies for subscriptions
CREATE POLICY "Members can view their own subscriptions" ON public.subscriptions
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Members can update their own subscriptions" ON public.subscriptions
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Authenticated members can insert subscriptions" ON public.subscriptions
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Admins can view all subscriptions" ON public.subscriptions
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- Verify table was created
SELECT 
    'Subscriptions table created successfully!' as message,
    schemaname, 
    tablename, 
    rowsecurity as rls_enabled
FROM pg_tables 
WHERE tablename = 'subscriptions';

-- Show RLS policies
SELECT 
    'RLS Policies:' as section,
    policyname,
    cmd as command_type
FROM pg_policies 
WHERE tablename = 'subscriptions';
