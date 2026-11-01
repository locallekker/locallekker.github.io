-- Add logo_url column to businesses table for trusted partner branding
-- Migration: add_logo_url_to_businesses

BEGIN;

-- Add logo_url column to businesses table
ALTER TABLE public.businesses
ADD COLUMN IF NOT EXISTS logo_url TEXT;

-- Add comment for clarity
COMMENT ON COLUMN public.businesses.logo_url IS 'URL to trusted partner logo stored in Supabase storage (partner-logos bucket)';

-- Create storage bucket for partner logos if it doesn't exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('partner-logos', 'partner-logos', true)
ON CONFLICT (id) DO NOTHING;

-- Add RLS policies for partner logos storage bucket
-- Drop existing policies first (if they exist)
DROP POLICY IF EXISTS "Trusted partners can upload their logos" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can update their logos" ON storage.objects;
DROP POLICY IF EXISTS "Trusted partners can delete their logos" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view partner logos" ON storage.objects;

-- Trusted partners can upload their own logos
CREATE POLICY "Trusted partners can upload their logos"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'partner-logos' AND
    auth.uid()::text = (storage.foldername(name))[1] AND
    EXISTS (
        SELECT 1 FROM businesses
        WHERE owner_member_id = auth.uid()
    )
);

-- Trusted partners can update their own logos
CREATE POLICY "Trusted partners can update their logos"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'partner-logos' AND
    auth.uid()::text = (storage.foldername(name))[1] AND
    EXISTS (
        SELECT 1 FROM businesses
        WHERE owner_member_id = auth.uid()
    )
);

-- Trusted partners can delete their own logos
CREATE POLICY "Trusted partners can delete their logos"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'partner-logos' AND
    auth.uid()::text = (storage.foldername(name))[1] AND
    EXISTS (
        SELECT 1 FROM businesses
        WHERE owner_member_id = auth.uid()
    )
);

-- Everyone can view logos (public access)
CREATE POLICY "Anyone can view partner logos"
ON storage.objects FOR SELECT
USING (bucket_id = 'partner-logos');

COMMIT;
