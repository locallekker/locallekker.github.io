-- Find "That Old Oak" business
SELECT 
    b.id,
    b.name,
    b.owner_member_id,
    b.logo_url,
    p.name as owner_name,
    p.email
FROM businesses b
LEFT JOIN profiles p ON b.owner_member_id = p.id
WHERE LOWER(b.name) LIKE '%oak%'
   OR LOWER(b.name) LIKE '%that old%';

-- Check all businesses for that partner
SELECT * FROM businesses 
WHERE name IN ('That Old Oak', 'Heartwood Homestead')
   OR owner_member_id IN (
       SELECT id FROM profiles 
       WHERE email LIKE '%oak%' OR email LIKE '%heartwood%'
   );
