-- Debug query to check banking notifications
SELECT 
  id,
  user_id,
  type,
  title,
  data,
  is_read,
  created_at
FROM notifications
WHERE type = 'banking_details_added'
ORDER BY created_at DESC
LIMIT 10;

-- Check admin users
SELECT 
  id,
  role,
  email
FROM profiles
WHERE role = 'admin'
LIMIT 5;

-- Check if OLD OAK notifications exist
SELECT 
  id,
  user_id,
  type,
  data,
  is_read,
  created_at
FROM notifications
WHERE data::text LIKE '%old oak%' 
  OR data::text LIKE '%Old Oak%'
  OR data::text LIKE '%OLD OAK%'
ORDER BY created_at DESC
LIMIT 10;
