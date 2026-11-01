-- Fix That Old Oak logo URL to point to the correct file in storage

UPDATE businesses
SET 
    logo_url = 'https://qdrotavcmmevhgveodcp.supabase.co/storage/v1/object/public/partner-logos/1916d77f-596f-4e9f-825f-dedf7a11bbf8/logo_1764755167228.jpg',
    updated_at = NOW()
WHERE owner_member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';

-- Verify the update
SELECT 
    name,
    logo_url,
    updated_at,
        CASE 
                WHEN EXISTS (
                        SELECT 1 FROM storage.objects 
                        WHERE bucket_id = 'partner-logos' 
                            AND (
                                -- Some setups store full path in name, others just filename
                                name = '1916d77f-596f-4e9f-825f-dedf7a11bbf8/logo_1764755167228.jpg'
                                OR (
                                    owner = '1916d77f-596f-4e9f-825f-dedf7a11bbf8'
                                    AND name LIKE '%logo_1764755167228.jpg'
                                )
                            )
                ) THEN '✅ File EXISTS in storage'
                ELSE '❌ File NOT FOUND'
        END as verification
FROM businesses
WHERE owner_member_id = '1916d77f-596f-4e9f-825f-dedf7a11bbf8';
