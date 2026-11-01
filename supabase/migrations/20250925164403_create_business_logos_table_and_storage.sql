-- Create business_logos table for logo scanner functionality
CREATE TABLE IF NOT EXISTS business_logos (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    logo_url TEXT NOT NULL,
    business_name TEXT NOT NULL,
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_business_logos_business_id ON business_logos(business_id);
CREATE INDEX IF NOT EXISTS idx_business_logos_active ON business_logos(is_active);
CREATE INDEX IF NOT EXISTS idx_business_logos_uploaded_at ON business_logos(uploaded_at DESC);

-- Enable RLS (Row Level Security)
ALTER TABLE business_logos ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Business owners can view their own logos" ON business_logos
    FOR SELECT USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can insert their own logos" ON business_logos
    FOR INSERT WITH CHECK (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can update their own logos" ON business_logos
    FOR UPDATE USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can delete their own logos" ON business_logos
    FOR DELETE USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- Create storage bucket for business logos
INSERT INTO storage.buckets (id, name, public)
VALUES ('business-logos', 'business-logos', true)
ON CONFLICT (id) DO NOTHING;

-- Create storage policies for business logos
CREATE POLICY "Business owners can view their logos" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'business-logos' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can upload their logos" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'business-logos' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can update their logos" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'business-logos' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can delete their logos" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'business-logos' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION update_business_logos_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_business_logos_updated_at
    BEFORE UPDATE ON business_logos
    FOR EACH ROW
    EXECUTE FUNCTION update_business_logos_updated_at();