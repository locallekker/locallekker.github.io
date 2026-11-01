-- Add RLS policies for deal images in business-bills bucket
-- This allows trusted partners to upload images for their deals

-- Create policy for trusted partners to upload deal images
DROP POLICY IF EXISTS "Trusted partners can upload deal images" ON storage.objects;
CREATE POLICY "Trusted partners can upload deal images" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
                (storage.foldername(name))[1] = auth.uid()::text
    );

-- Create policy for trusted partners to view deal images
DROP POLICY IF EXISTS "Trusted partners can view deal images" ON storage.objects;
CREATE POLICY "Trusted partners can view deal images" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
                (storage.foldername(name))[1] = auth.uid()::text
    );

-- Create policy for trusted partners to update deal images
DROP POLICY IF EXISTS "Trusted partners can update deal images" ON storage.objects;
CREATE POLICY "Trusted partners can update deal images" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
                (storage.foldername(name))[1] = auth.uid()::text
    );

-- Create policy for trusted partners to delete deal images
DROP POLICY IF EXISTS "Trusted partners can delete deal images" ON storage.objects;
CREATE POLICY "Trusted partners can delete deal images" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
                (storage.foldername(name))[1] = auth.uid()::text
    );

-- Also allow members to view deal images (for the deals page)
DROP POLICY IF EXISTS "Members can view deal images" ON storage.objects;
CREATE POLICY "Members can view deal images" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%'
    );

-- Allow admins to manage deal images when the business allows admin deal creation.
-- Admins will upload into a folder using the trusted partner ID as the first
-- segment of the path: 'deal_images/{trusted_partner_id}/...'. The policy
-- checks that there's a matching discount owned by that trusted partner and
-- that the businesses.allow_admin_deal_creation flag is true and that the
-- authenticated user is an admin in `memberships`.
DROP POLICY IF EXISTS "Admins can manage deal images" ON storage.objects;
CREATE POLICY "Admins can manage deal images" ON storage.objects
    FOR ALL USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
        EXISTS (
            SELECT 1 FROM public.businesses b
            JOIN public.memberships m ON m.user_id = auth.uid() AND m.role = 'admin'
            WHERE b.owner_member_id::text = (storage.foldername(name))[1]
              AND COALESCE(b.allow_admin_deal_creation, false) = true
        )
    ) WITH CHECK (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
        EXISTS (
            SELECT 1 FROM public.businesses b
            JOIN public.memberships m ON m.user_id = auth.uid() AND m.role = 'admin'
            WHERE b.owner_member_id::text = (storage.foldername(name))[1]
              AND COALESCE(b.allow_admin_deal_creation, false) = true
        )
    );