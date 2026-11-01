-- Migration: Completely disable the trigger to test if it's causing the database error
-- This will temporarily disable the trigger to isolate the issue

BEGIN;

-- Drop the trigger completely to test if it's causing the database error
DROP TRIGGER IF EXISTS trigger_automatic_role_assignment ON auth.users;

-- Keep the function for now in case we need to re-enable it later
-- The function will just log and return NEW without doing any database operations

COMMIT;