-- Create processed_bills table for receipt scanning functionality
CREATE TABLE IF NOT EXISTS processed_bills (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    discount_id UUID NOT NULL,
    partner_id TEXT NOT NULL,
    receipt_data JSONB NOT NULL,
    original_total DECIMAL(10,2) NOT NULL,
    discount_amount DECIMAL(10,2) NOT NULL,
    discounted_total DECIMAL(10,2) NOT NULL,
    image_url TEXT,
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_processed_bills_user_id ON processed_bills(user_id);
CREATE INDEX IF NOT EXISTS idx_processed_bills_discount_id ON processed_bills(discount_id);
CREATE INDEX IF NOT EXISTS idx_processed_bills_partner_id ON processed_bills(partner_id);
CREATE INDEX IF NOT EXISTS idx_processed_bills_processed_at ON processed_bills(processed_at DESC);

-- Enable RLS (Row Level Security)
ALTER TABLE processed_bills ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Users can view their own processed bills" ON processed_bills
    FOR SELECT USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can insert their own processed bills" ON processed_bills
    FOR INSERT WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can update their own processed bills" ON processed_bills
    FOR UPDATE USING ((SELECT auth.uid()) = user_id);

-- Create storage bucket for receipt images
INSERT INTO storage.buckets (id, name, public)
VALUES ('receipt-images', 'receipt-images', true)
ON CONFLICT (id) DO NOTHING;

-- Create storage policies for receipt images
CREATE POLICY "Users can view receipt images" ON storage.objects
    FOR SELECT USING (bucket_id = 'receipt-images');

CREATE POLICY "Users can upload receipt images" ON storage.objects
    FOR INSERT WITH CHECK (bucket_id = 'receipt-images' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "Users can update their own receipt images" ON storage.objects
    FOR UPDATE USING (bucket_id = 'receipt-images' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "Users can delete their own receipt images" ON storage.objects
    FOR DELETE USING (bucket_id = 'receipt-images' AND auth.uid()::text = (storage.foldername(name))[1]);

-- Create function to get user processed bills statistics
CREATE OR REPLACE FUNCTION get_user_bill_statistics(user_uuid UUID)
RETURNS TABLE (
    total_bills BIGINT,
    total_saved DECIMAL(10,2),
    total_spent DECIMAL(10,2),
    most_used_partner TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) as total_bills,
        COALESCE(SUM(discount_amount), 0) as total_saved,
        COALESCE(SUM(original_total), 0) as total_spent,
        (
            SELECT partner_id
            FROM processed_bills pb2
            WHERE pb2.user_id = user_uuid
            GROUP BY partner_id
            ORDER BY COUNT(*) DESC
            LIMIT 1
        ) as most_used_partner
    FROM processed_bills pb
    WHERE pb.user_id = user_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER update_processed_bills_updated_at
    BEFORE UPDATE ON processed_bills
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();