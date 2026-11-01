-- Manually update That Old Oak logo_url
UPDATE businesses
SET logo_url = 'https://qdrotavcmmevhgveodcp.supabase.co/storage/v1/object/public/partner-logos/1916d77f-596f-4e9f-825f-dedf7a11bbf8/logo_1764701707070.jpg'
WHERE owner_member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- Verify the update
SELECT 
    b.id,
    b.name,
    b.owner_member_id,
    b.logo_url
FROM businesses b
WHERE b.name = 'That Old Oak';
