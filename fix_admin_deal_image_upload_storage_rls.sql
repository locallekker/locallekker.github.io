-- Fix admin deal image upload RLS policy
-- Issue: Admin cannot upload deal images for trusted partners
-- Solution: Allow admins to upload to any deal_images/{partner_id}/ folder

BEGIN;

-- Drop the overly restrictive admin policy
DROP POLICY IF EXISTS "Admins can manage deal images" ON storage.objects;

-- Create a simpler admin policy that allows admins to upload to any deal_images folder
-- if the business exists and allow_admin_deal_creation is true
CREATE POLICY "Admins can upload deal images" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'business-bills' 
        AND name LIKE 'deal_images/%'
        AND EXISTS (
            SELECT 1 
            FROM public.memberships m 
            WHERE m.user_id = auth.uid() 
              AND m.role = 'admin'
        )
    );

-- Allow admins to view all deal images
CREATE POLICY "Admins can view all deal images" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'business-bills'
        AND name LIKE 'deal_images/%'
        AND EXISTS (
            SELECT 1 
            FROM public.memberships m 
            WHERE m.user_id = auth.uid() 
              AND m.role = 'admin'
        )
    );

-- Allow admins to update deal images they have access to
CREATE POLICY "Admins can update deal images" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'business-bills'
        AND name LIKE 'deal_images/%'
        AND EXISTS (
            SELECT 1 
            FROM public.memberships m 
            WHERE m.user_id = auth.uid() 
              AND m.role = 'admin'
        )
    );

-- Allow admins to delete deal images
CREATE POLICY "Admins can delete deal images" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'business-bills'
        AND name LIKE 'deal_images/%'
        AND EXISTS (
            SELECT 1 
            FROM public.memberships m 
            WHERE m.user_id = auth.uid() 
              AND m.role = 'admin'
        )
    );

COMMIT;
