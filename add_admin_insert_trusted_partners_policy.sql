-- Migration: Allow admins to insert trusted_partner records on behalf of users
-- Reason: Existing insert policy only allows auth.uid() = user_id, blocking admin-created accounts.
-- Safe to run multiple times (DROP POLICY IF EXISTS)

-- Enable: Admin insert
DROP POLICY IF EXISTS "Admins can insert trusted_partners" ON public.trusted_partners;
CREATE POLICY "Admins can insert trusted_partners" ON public.trusted_partners
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- Admin UPDATE policy (idempotent)
DROP POLICY IF EXISTS "Admins can update trusted_partners" ON public.trusted_partners;
CREATE POLICY "Admins can update trusted_partners" ON public.trusted_partners
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- Admin DELETE policy (idempotent)
DROP POLICY IF EXISTS "Admins can delete trusted_partners" ON public.trusted_partners;
CREATE POLICY "Admins can delete trusted_partners" ON public.trusted_partners
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.memberships
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

-- Verification queries (run after applying):
-- 1. As admin session: INSERT INTO public.trusted_partners(user_id,business_name) VALUES ('<new_user_uuid>','Test Business');
-- 2. As non-admin: same insert should fail.
-- 3. SELECT * FROM public.trusted_partners LIMIT 5; -- should show new row.
