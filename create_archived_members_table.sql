-- =====================================================
-- ARCHIVED MEMBERS TABLE
-- Stores deleted member data for re-signup autofill
-- =====================================================

-- Create archived_members table to preserve member data after deletion
CREATE TABLE IF NOT EXISTS public.archived_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_user_id UUID NOT NULL, -- Original auth user ID (now deleted)
    email TEXT NOT NULL,
    name TEXT,
    surname TEXT,
    street TEXT,
    suburb TEXT,
    city TEXT,
    province TEXT,
    contact TEXT,
    gender TEXT,
    ethnicity TEXT,
    date_of_birth TIMESTAMP WITH TIME ZONE,
    
    -- Metadata
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_by UUID REFERENCES auth.users(id), -- Admin who deleted the member
    deletion_reason TEXT,
    
    -- Subscription info at time of deletion
    last_subscription_status TEXT,
    last_subscription_end_date TIMESTAMP WITH TIME ZONE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index for fast email lookup during signup
CREATE INDEX IF NOT EXISTS idx_archived_members_email 
ON public.archived_members(LOWER(email));

-- Create index on original_user_id for reference
CREATE INDEX IF NOT EXISTS idx_archived_members_original_user_id 
ON public.archived_members(original_user_id);

-- Enable RLS
ALTER TABLE public.archived_members ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Only admins and the signup flow can access archived members
-- Drop existing policies first to make script idempotent
DROP POLICY IF EXISTS "Admins can view all archived members" ON public.archived_members;
CREATE POLICY "Admins can view all archived members" 
ON public.archived_members
FOR SELECT 
USING (
    EXISTS (
        SELECT 1 FROM public.memberships
        WHERE user_id = auth.uid() AND role = 'admin'
    )
);

DROP POLICY IF EXISTS "Service role can insert archived members" ON public.archived_members;
CREATE POLICY "Service role can insert archived members" 
ON public.archived_members
FOR INSERT 
WITH CHECK (true); -- Function uses SECURITY DEFINER

DROP POLICY IF EXISTS "Anon users can check archived members by email" ON public.archived_members;
CREATE POLICY "Anon users can check archived members by email" 
ON public.archived_members
FOR SELECT 
USING (true); -- Allow public read for signup flow

-- Grant permissions
GRANT SELECT ON public.archived_members TO anon, authenticated;
GRANT INSERT ON public.archived_members TO authenticated;
