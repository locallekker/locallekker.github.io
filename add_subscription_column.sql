-- Add subscription column to profiles table
ALTER TABLE public.profiles 
ADD COLUMN subscription TEXT DEFAULT 'pending';

-- Update existing records to have appropriate subscription status based on role
UPDATE public.profiles 
SET subscription = CASE 
    WHEN role = 'user' THEN 'pending'
    ELSE 'active'
END
WHERE subscription IS NULL;

-- Verify the column was added and populated
SELECT 
    id, 
    role, 
    subscription, 
    name, 
    email 
FROM 
    public.profiles 
LIMIT 5;
