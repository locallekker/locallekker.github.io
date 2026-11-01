-- CRITICAL FIX: Admin deal image upload RLS policy
-- BUG FOUND: The policies were using b.name instead of storage.objects.name
-- This caused the policy to compare business name with the file path, which always failed

-- Step 1: Drop ALL existing deal image policies
DO $$ 
DECLARE
    pol record;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE schemaname = 'storage' 
        AND tablename = 'objects'
        AND policyname LIKE '%deal image%'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', pol.policyname);
    END LOOP;
END $$;

-- Step 2: Create trusted partner policies (for when they manage their own deals)
CREATE POLICY "Trusted partners can upload deal images" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
        split_part(name, '/', 2) = auth.uid()::text
    );

CREATE POLICY "Trusted partners can view deal images" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
        split_part(name, '/', 2) = auth.uid()::text
    );

CREATE POLICY "Trusted partners can update deal images" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
        split_part(name, '/', 2) = auth.uid()::text
    );

CREATE POLICY "Trusted partners can delete deal images" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
        split_part(name, '/', 2) = auth.uid()::text
    );

-- Step 3: Allow all members to view deal images
CREATE POLICY "Members can view deal images" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%'
    );

-- Step 4: Create admin policies with CORRECT reference to storage.objects.name
-- CRITICAL FIX: Use storage.objects.name, NOT b.name
CREATE POLICY "Admins can upload deal images for authorized partners" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
        EXISTS (
            SELECT 1 
            FROM public.memberships m 
            WHERE m.user_id = auth.uid() 
              AND m.role = 'admin'
        ) AND
        EXISTS (
            SELECT 1 
            FROM public.businesses b
            WHERE b.owner_member_id::text = split_part(storage.objects.name, '/', 2)
              AND COALESCE(b.allow_admin_deal_creation, false) = true
        )
    );

CREATE POLICY "Admins can view deal images for authorized partners" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
        EXISTS (
            SELECT 1 
            FROM public.memberships m 
            WHERE m.user_id = auth.uid() 
              AND m.role = 'admin'
        ) AND
        EXISTS (
            SELECT 1 
            FROM public.businesses b
            WHERE b.owner_member_id::text = split_part(storage.objects.name, '/', 2)
              AND COALESCE(b.allow_admin_deal_creation, false) = true
        )
    );

CREATE POLICY "Admins can update deal images for authorized partners" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
        EXISTS (
            SELECT 1 
            FROM public.memberships m 
            WHERE m.user_id = auth.uid() 
              AND m.role = 'admin'
        ) AND
        EXISTS (
            SELECT 1 
            FROM public.businesses b
            WHERE b.owner_member_id::text = split_part(storage.objects.name, '/', 2)
              AND COALESCE(b.allow_admin_deal_creation, false) = true
        )
    );

CREATE POLICY "Admins can delete deal images for authorized partners" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'business-bills' AND
        name LIKE 'deal_images/%' AND
        EXISTS (
            SELECT 1 
            FROM public.memberships m 
            WHERE m.user_id = auth.uid() 
              AND m.role = 'admin'
        ) AND
        EXISTS (
            SELECT 1 
            FROM public.businesses b
            WHERE b.owner_member_id::text = split_part(storage.objects.name, '/', 2)
              AND COALESCE(b.allow_admin_deal_creation, false) = true
        )
    );
