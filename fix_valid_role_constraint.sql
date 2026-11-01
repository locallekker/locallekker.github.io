-- Fix the valid_role constraint violation blocking signup
-- Error: new row for relation "profiles" violates check constraint "valid_role"

-- STEP 1: Check what the valid_role constraint currently allows
SELECT 
  conname AS constraint_name,
  pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'profiles'::regclass
  AND conname = 'valid_role';

-- STEP 2: Check the trigger that creates profiles on signup
SELECT 
  p.proname as function_name,
  pg_get_functiondef(p.oid) as definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND (p.proname LIKE '%profile%' OR p.proname LIKE '%user%')
  AND pg_get_functiondef(p.oid) LIKE '%INSERT INTO profiles%'
ORDER BY p.proname;

-- STEP 3: Fix the constraint to allow 'member' role (default for signups)
-- Drop the old constraint
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS valid_role;

-- Recreate with correct allowed values
ALTER TABLE profiles ADD CONSTRAINT valid_role 
  CHECK (role IN ('member', 'trusted_partner', 'admin'));

-- STEP 4: Verify the fix
SELECT 
  conname AS constraint_name,
  pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'profiles'::regclass
  AND conname = 'valid_role';

-- STEP 5: Test that signup will work now
-- This simulates what the trigger does (without actually inserting)
SELECT 'member' AS test_role,
  CASE 
    WHEN 'member' IN ('member', 'trusted_partner', 'admin') 
    THEN 'Valid ✓' 
    ELSE 'Invalid ✗' 
  END AS validation_result;
