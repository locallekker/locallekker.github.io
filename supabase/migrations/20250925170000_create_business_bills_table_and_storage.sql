-- Create business_bills table for bill scanner functionality
CREATE TABLE IF NOT EXISTS business_bills (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    bill_url TEXT NOT NULL,
    business_name TEXT NOT NULL,
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,
    extracted_features JSONB, -- Store extracted features for OCR matching
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_business_bills_business_id ON business_bills(business_id);
CREATE INDEX IF NOT EXISTS idx_business_bills_active ON business_bills(is_active);
CREATE INDEX IF NOT EXISTS idx_business_bills_uploaded_at ON business_bills(uploaded_at DESC);

-- Enable RLS (Row Level Security)
ALTER TABLE business_bills ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Business owners can view their own bills" ON business_bills
    FOR SELECT USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can insert their own bills" ON business_bills
    FOR INSERT WITH CHECK (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can update their own bills" ON business_bills
    FOR UPDATE USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can delete their own bills" ON business_bills
    FOR DELETE USING (
        business_id IN (
            SELECT id FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- Create storage bucket for business bills
INSERT INTO storage.buckets (id, name, public)
VALUES ('business-bills', 'business-bills', true)
ON CONFLICT (id) DO NOTHING;

-- Create storage policies for business bills
CREATE POLICY "Business owners can view their bills" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'business-bills' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can upload their bills" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'business-bills' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can update their bills" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'business-bills' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

CREATE POLICY "Business owners can delete their bills" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'business-bills' AND
        (storage.foldername(name))[1] IN (
            SELECT id::text FROM businesses WHERE owner_member_id = auth.uid()
        )
    );

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION update_business_bills_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER update_business_bills_updated_at
    BEFORE UPDATE ON business_bills
    FOR EACH ROW
    EXECUTE FUNCTION update_business_bills_updated_at();