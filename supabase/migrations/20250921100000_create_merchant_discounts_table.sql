-- Create merchant_discounts table
CREATE TABLE IF NOT EXISTS merchant_discounts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    merchant_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    percentage DECIMAL(5,2) DEFAULT 0,
    fixed_amount DECIMAL(10,2),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Ensure either percentage or fixed_amount is set, but not both
    CONSTRAINT discount_type_check CHECK (
        (percentage > 0 AND fixed_amount IS NULL) OR
        (percentage = 0 AND fixed_amount IS NOT NULL AND fixed_amount > 0)
    )
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_merchant_discounts_merchant_id ON merchant_discounts(merchant_id);
CREATE INDEX IF NOT EXISTS idx_merchant_discounts_active ON merchant_discounts(is_active);

-- Enable RLS
ALTER TABLE merchant_discounts ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can view their own discounts" ON merchant_discounts
    FOR SELECT USING (auth.uid() = merchant_id);

CREATE POLICY "Users can insert their own discounts" ON merchant_discounts
    FOR INSERT WITH CHECK (auth.uid() = merchant_id);

CREATE POLICY "Users can update their own discounts" ON merchant_discounts
    FOR UPDATE USING (auth.uid() = merchant_id);

CREATE POLICY "Users can delete their own discounts" ON merchant_discounts
    FOR DELETE USING (auth.uid() = merchant_id);

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_merchant_discounts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update updated_at
CREATE TRIGGER update_merchant_discounts_updated_at_trigger
    BEFORE UPDATE ON merchant_discounts
    FOR EACH ROW
    EXECUTE FUNCTION update_merchant_discounts_updated_at();