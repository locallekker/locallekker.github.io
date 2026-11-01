-- Fix duplicate subscription records for the same user.
-- Keeps only the most recently created subscription per user_id.
-- Run this once to clean up existing duplicates.

-- Step 1: View affected users (diagnostic)
SELECT user_id, COUNT(*) AS record_count
FROM public.subscriptions
GROUP BY user_id
HAVING COUNT(*) > 1;

-- Step 2: Delete older duplicates, keeping newest per user
DELETE FROM public.subscriptions
WHERE id NOT IN (
    SELECT DISTINCT ON (user_id) id
    FROM public.subscriptions
    ORDER BY user_id, created_at DESC
);

-- Step 3: Add unique constraint to prevent future duplicates
ALTER TABLE public.subscriptions
ADD CONSTRAINT subscriptions_user_id_unique UNIQUE (user_id);

-- Step 4: Verify — should show 0 duplicates
SELECT user_id, COUNT(*) AS record_count
FROM public.subscriptions
GROUP BY user_id
HAVING COUNT(*) > 1;
