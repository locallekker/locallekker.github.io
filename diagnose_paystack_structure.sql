-- Check Paystack and Payment Data for Trusted Partners
-- Run this in Supabase SQL Editor

-- 1. Check which tables have Paystack fields
SELECT 
    table_name,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
    column_name LIKE '%paystack%' OR 
    column_name LIKE '%recipient%' OR
    column_name LIKE '%payment%code%'
  )
ORDER BY table_name, column_name;

-- 2. Check profiles table for Paystack fields
SELECT 
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'profiles'
ORDER BY column_name;

-- 3. Check trusted_partners or businesses for Paystack fields
SELECT 
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'businesses'
ORDER BY column_name;

-- 4. Check for payment-related tables
SELECT 
    table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND (
    table_name LIKE '%payment%' OR
    table_name LIKE '%paystack%' OR
    table_name LIKE '%pending%'
  )
ORDER BY table_name;

-- 5. Sample query to see Paystack data structure in profiles
/*
SELECT 
    id,
    email,
    paystack_recipient_code,
    paystack_authorization_code,
    paystack_subaccount_code,
    paystack_customer_code
FROM public.profiles
LIMIT 1;
*/
