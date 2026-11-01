-- Add unique key field to trusted_partners table
ALTER TABLE public.trusted_partners 
ADD COLUMN IF NOT EXISTS unique_key TEXT UNIQUE;

-- Add banking details to profiles table for trusted partner members
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS bank_account_holder TEXT,
ADD COLUMN IF NOT EXISTS bank_name TEXT,
ADD COLUMN IF NOT EXISTS bank_account_number TEXT,
ADD COLUMN IF NOT EXISTS bank_branch_code TEXT,
ADD COLUMN IF NOT EXISTS bank_account_type TEXT,
ADD COLUMN IF NOT EXISTS is_tp_member BOOLEAN DEFAULT FALSE;

-- Create index on unique_key for faster lookups
CREATE INDEX IF NOT EXISTS idx_trusted_partners_unique_key ON public.trusted_partners(unique_key);

-- Function to generate unique key for trusted partners
CREATE OR REPLACE FUNCTION generate_tp_unique_key()
RETURNS TEXT AS $$
DECLARE
    key TEXT;
    key_exists BOOLEAN;
BEGIN
    LOOP
        -- Generate a random 12-character alphanumeric key
        key := upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for 12));
        
        -- Check if key already exists
        SELECT EXISTS(SELECT 1 FROM public.trusted_partners WHERE unique_key = key) INTO key_exists;
        
        -- If key doesn't exist, return it
        IF NOT key_exists THEN
            RETURN key;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically generate unique key for new trusted partners
CREATE OR REPLACE FUNCTION set_tp_unique_key()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.unique_key IS NULL THEN
        NEW.unique_key := generate_tp_unique_key();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_set_tp_unique_key ON public.trusted_partners;
CREATE TRIGGER trigger_set_tp_unique_key
    BEFORE INSERT ON public.trusted_partners
    FOR EACH ROW
    EXECUTE FUNCTION set_tp_unique_key();

-- Generate keys for existing trusted partners
UPDATE public.trusted_partners 
SET unique_key = generate_tp_unique_key() 
WHERE unique_key IS NULL;
