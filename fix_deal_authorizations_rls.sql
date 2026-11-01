-- Fix deal_authorizations RLS policies to use business_id instead of trusted_partner_id
-- This fixes the issue where approved authorizations still show in pending tab

-- First, check current structure
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'deal_authorizations'
ORDER BY ordinal_position;

-- Check current policies
SELECT 
    policyname,
    cmd,
    permissive,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'deal_authorizations'
ORDER BY cmd, policyname;

-- Drop old policies
DROP POLICY IF EXISTS "Members can view their authorizations" ON deal_authorizations;
DROP POLICY IF EXISTS "Members can insert their authorizations" ON deal_authorizations;
DROP POLICY IF EXISTS "Business owners can view their authorizations" ON deal_authorizations;
DROP POLICY IF EXISTS "Business owners can update their authorizations" ON deal_authorizations;

-- Create corrected policies using business_id
CREATE POLICY "Members can view their authorizations" ON deal_authorizations
    FOR SELECT USING (member_id = auth.uid());

CREATE POLICY "Members can insert their authorizations" ON deal_authorizations
    FOR INSERT WITH CHECK (member_id = auth.uid());

CREATE POLICY "Business owners can view their authorizations" ON deal_authorizations
    FOR SELECT USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can update their authorizations" ON deal_authorizations
    FOR UPDATE USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- Verify new policies
SELECT 
    policyname,
    cmd,
    permissive,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'deal_authorizations'
ORDER BY cmd, policyname;

-- Test query: Check if current user can see deal_authorizations
-- This shows ALL authorizations (may be restricted by RLS)
SELECT 
    da.id,
    da.status,
    da.member_id,
    da.business_id,
    b.owner_member_id as business_owner,
    b.name as business_name,
    da.amount,
    da.payment_method,
    LEFT(da.notes, 60) as notes_preview,
    da.created_at,
    da.updated_at,
    da.approved_at,
    CASE 
        WHEN da.status = 'pending' THEN '🟡 PENDING - Should show in Pending tab'
        WHEN da.status = 'approved' AND da.completed_at IS NULL THEN '🟢 APPROVED - Awaiting Payment'
        WHEN da.status = 'approved' AND da.completed_at IS NOT NULL THEN '✅ APPROVED - Payment Completed'
        WHEN da.status = 'rejected' THEN '🔴 REJECTED'
        ELSE '❓ Unknown'
    END as display_status
FROM deal_authorizations da
LEFT JOIN businesses b ON da.business_id = b.id
ORDER BY da.created_at DESC
LIMIT 20;

-- Check specifically for pending authorizations
SELECT 
    COUNT(*) as count,
    'Total PENDING authorizations (should show in app)' as description
FROM deal_authorizations 
WHERE status = 'pending';

-- If you see the authorization approved successfully message but it still shows as pending,
-- run this to check if the update actually happened:
SELECT 
    id,
    status,
    updated_at,
    approved_at,
    'Recently updated authorizations' as note
FROM deal_authorizations
WHERE updated_at > NOW() - INTERVAL '10 minutes'
ORDER BY updated_at DESC;
