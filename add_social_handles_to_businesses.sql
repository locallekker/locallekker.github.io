-- Add social media handles and website/email to businesses table
-- These will be displayed to members when viewing trusted partners

ALTER TABLE businesses 
ADD COLUMN IF NOT EXISTS facebook_handle TEXT,
ADD COLUMN IF NOT EXISTS instagram_handle TEXT,
ADD COLUMN IF NOT EXISTS website_url TEXT,
ADD COLUMN IF NOT EXISTS business_email TEXT;

-- Comment the columns for clarity
COMMENT ON COLUMN businesses.facebook_handle IS 'Facebook page URL or username for the business';
COMMENT ON COLUMN businesses.instagram_handle IS 'Instagram handle (without @) for the business';
COMMENT ON COLUMN businesses.website_url IS 'Business website URL';
COMMENT ON COLUMN businesses.business_email IS 'Public business email for customer contact';
