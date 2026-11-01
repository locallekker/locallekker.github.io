-- =============================================================================
-- CASCADE DELETE FOR TRUSTED PARTNER DATA
-- =============================================================================
-- This script ensures that when a trusted partner is deleted from auth.users,
-- all their related data across all tables is automatically deleted.
-- 
-- IMPORTANT: This modifies foreign key constraints to use ON DELETE CASCADE
-- Run this ONCE on your database to set up the cascade behavior.
-- =============================================================================

-- =============================================================================
-- 1. PROFILES TABLE
-- =============================================================================
-- User profile will cascade delete when auth user is deleted
-- (Already has FK to auth.users(id) with CASCADE in most schemas)
ALTER TABLE public.profiles 
DROP CONSTRAINT IF EXISTS profiles_id_fkey;

ALTER TABLE public.profiles 
ADD CONSTRAINT profiles_id_fkey 
FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- =============================================================================
-- 2. MEMBERSHIPS TABLE
-- =============================================================================
-- User membership will cascade delete when auth user is deleted
ALTER TABLE public.memberships 
DROP CONSTRAINT IF EXISTS memberships_user_id_fkey;

ALTER TABLE public.memberships 
ADD CONSTRAINT memberships_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- =============================================================================
-- 3. TRUSTED_PARTNERS TABLE
-- =============================================================================
-- Trusted partner record will cascade delete when auth user is deleted
ALTER TABLE public.trusted_partners 
DROP CONSTRAINT IF EXISTS trusted_partners_user_id_fkey;

ALTER TABLE public.trusted_partners 
ADD CONSTRAINT trusted_partners_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- =============================================================================
-- 4. BUSINESSES TABLE
-- =============================================================================
-- Business owned by trusted partner will cascade delete when auth user is deleted
ALTER TABLE public.businesses 
DROP CONSTRAINT IF EXISTS businesses_owner_member_id_fkey;

ALTER TABLE public.businesses 
ADD CONSTRAINT businesses_owner_member_id_fkey 
FOREIGN KEY (owner_member_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- =============================================================================
-- 5. TRUSTED_PARTNER_BANK_ACCOUNTS TABLE
-- =============================================================================
-- Bank accounts will cascade delete when auth user is deleted
ALTER TABLE public.trusted_partner_bank_accounts 
DROP CONSTRAINT IF EXISTS trusted_partner_bank_accounts_user_id_fkey;

ALTER TABLE public.trusted_partner_bank_accounts 
ADD CONSTRAINT trusted_partner_bank_accounts_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- =============================================================================
-- 6. TRUSTED_PARTNER_DISCOUNTS TABLE
-- =============================================================================
-- Discounts will cascade delete when auth user OR business is deleted
ALTER TABLE public.trusted_partner_discounts 
DROP CONSTRAINT IF EXISTS trusted_partner_discounts_trusted_partner_id_fkey;

ALTER TABLE public.trusted_partner_discounts 
ADD CONSTRAINT trusted_partner_discounts_trusted_partner_id_fkey 
FOREIGN KEY (trusted_partner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Add business_id column if it doesn't exist (for older schemas)
ALTER TABLE public.trusted_partner_discounts 
ADD COLUMN IF NOT EXISTS business_id UUID;

-- Populate business_id from trusted_partner_id for existing records
UPDATE public.trusted_partner_discounts
SET business_id = b.id
FROM public.businesses b
WHERE trusted_partner_discounts.trusted_partner_id = b.owner_member_id
AND trusted_partner_discounts.business_id IS NULL;

-- Add the foreign key constraint
ALTER TABLE public.trusted_partner_discounts 
DROP CONSTRAINT IF EXISTS trusted_partner_discounts_business_id_fkey;

ALTER TABLE public.trusted_partner_discounts 
ADD CONSTRAINT trusted_partner_discounts_business_id_fkey 
FOREIGN KEY (business_id) REFERENCES public.businesses(id) ON DELETE CASCADE;

-- =============================================================================
-- 7. DEAL_AUTHORIZATIONS TABLE
-- =============================================================================
-- Deal authorizations reference both member and business
-- When business is deleted (via trusted partner cascade), deals are deleted

-- Add missing columns if they don't exist
ALTER TABLE public.deal_authorizations 
ADD COLUMN IF NOT EXISTS member_id UUID;

ALTER TABLE public.deal_authorizations 
ADD COLUMN IF NOT EXISTS business_id UUID;

ALTER TABLE public.deal_authorizations 
ADD COLUMN IF NOT EXISTS trusted_partner_id UUID;

ALTER TABLE public.deal_authorizations 
ADD COLUMN IF NOT EXISTS discount_id UUID;

-- Add foreign key constraints
ALTER TABLE public.deal_authorizations 
DROP CONSTRAINT IF EXISTS deal_authorizations_member_id_fkey;

ALTER TABLE public.deal_authorizations 
ADD CONSTRAINT deal_authorizations_member_id_fkey 
FOREIGN KEY (member_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.deal_authorizations 
DROP CONSTRAINT IF EXISTS deal_authorizations_business_id_fkey;

ALTER TABLE public.deal_authorizations 
ADD CONSTRAINT deal_authorizations_business_id_fkey 
FOREIGN KEY (business_id) REFERENCES public.businesses(id) ON DELETE CASCADE;

ALTER TABLE public.deal_authorizations 
DROP CONSTRAINT IF EXISTS deal_authorizations_trusted_partner_id_fkey;

ALTER TABLE public.deal_authorizations 
ADD CONSTRAINT deal_authorizations_trusted_partner_id_fkey 
FOREIGN KEY (trusted_partner_id) REFERENCES public.businesses(id) ON DELETE CASCADE;

ALTER TABLE public.deal_authorizations 
DROP CONSTRAINT IF EXISTS deal_authorizations_discount_id_fkey;

ALTER TABLE public.deal_authorizations 
ADD CONSTRAINT deal_authorizations_discount_id_fkey 
FOREIGN KEY (discount_id) REFERENCES public.trusted_partner_discounts(id) ON DELETE SET NULL;

-- =============================================================================
-- 8. PROCESSED_BILLS TABLE
-- =============================================================================
-- Bills will cascade delete when member is deleted
-- Bills will SET NULL business_id when business is deleted (keeps bill history)
ALTER TABLE public.processed_bills 
DROP CONSTRAINT IF EXISTS processed_bills_member_id_fkey;

ALTER TABLE public.processed_bills 
ADD CONSTRAINT processed_bills_member_id_fkey 
FOREIGN KEY (member_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Add business_id column if it doesn't exist
ALTER TABLE public.processed_bills 
ADD COLUMN IF NOT EXISTS business_id UUID;

-- Add the foreign key constraint for business_id
ALTER TABLE public.processed_bills 
DROP CONSTRAINT IF EXISTS processed_bills_business_id_fkey;

ALTER TABLE public.processed_bills 
ADD CONSTRAINT processed_bills_business_id_fkey 
FOREIGN KEY (business_id) REFERENCES public.businesses(id) ON DELETE SET NULL;

-- =============================================================================
-- 9. NOTIFICATIONS TABLE
-- =============================================================================
-- Notifications will cascade delete when user is deleted
ALTER TABLE public.notifications 
DROP CONSTRAINT IF EXISTS notifications_user_id_fkey;

ALTER TABLE public.notifications 
ADD CONSTRAINT notifications_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- =============================================================================
-- 10. PAYMENTS TABLE
-- =============================================================================
-- Payments will cascade delete when user is deleted
ALTER TABLE public.payments 
DROP CONSTRAINT IF EXISTS payments_user_id_fkey;

ALTER TABLE public.payments 
ADD CONSTRAINT payments_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- =============================================================================
-- 11. SUBSCRIPTIONS TABLE
-- =============================================================================
-- Subscriptions will cascade delete when user is deleted
ALTER TABLE public.subscriptions 
DROP CONSTRAINT IF EXISTS subscriptions_user_id_fkey;

ALTER TABLE public.subscriptions 
ADD CONSTRAINT subscriptions_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- =============================================================================
-- 12. USER_QR_CODES TABLE
-- =============================================================================
-- QR codes will cascade delete when user is deleted
ALTER TABLE public.user_qr_codes 
DROP CONSTRAINT IF EXISTS user_qr_codes_user_id_fkey;

ALTER TABLE public.user_qr_codes 
ADD CONSTRAINT user_qr_codes_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- =============================================================================
-- 13. SUBSCRIPTION_RENEWALS TABLE (if exists)
-- =============================================================================
-- Subscription renewals will cascade delete when subscription is deleted
DO $$ 
BEGIN
    IF EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'subscription_renewals'
    ) THEN
        ALTER TABLE public.subscription_renewals 
        DROP CONSTRAINT IF EXISTS subscription_renewals_subscription_id_fkey;
        
        ALTER TABLE public.subscription_renewals 
        ADD CONSTRAINT subscription_renewals_subscription_id_fkey 
        FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id) ON DELETE CASCADE;
    END IF;
END $$;

-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================

-- Check all foreign key constraints with CASCADE behavior
SELECT 
    tc.table_name, 
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name,
    rc.delete_rule
FROM 
    information_schema.table_constraints AS tc 
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
      AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage AS ccu
      ON ccu.constraint_name = tc.constraint_name
      AND ccu.table_schema = tc.table_schema
    JOIN information_schema.referential_constraints AS rc
      ON rc.constraint_name = tc.constraint_name
      AND rc.constraint_schema = tc.table_schema
WHERE 
    tc.constraint_type = 'FOREIGN KEY' 
    AND tc.table_schema = 'public'
    AND (
        ccu.table_name = 'users' 
        OR ccu.table_name = 'profiles' 
        OR ccu.table_name = 'businesses'
        OR ccu.table_name = 'trusted_partner_discounts'
        OR ccu.table_name = 'subscriptions'
    )
ORDER BY 
    tc.table_name, kcu.column_name;

-- =============================================================================
-- SUMMARY OF CASCADE DELETE BEHAVIOR
-- =============================================================================
-- When a trusted partner (auth.users) is deleted:
--
-- 1. profiles → DELETED (their profile)
-- 2. memberships → DELETED (their role assignment)
-- 3. trusted_partners → DELETED (their trusted partner record)
-- 4. businesses → DELETED (their business entity)
--    ↳ trusted_partner_discounts → DELETED (all discounts for that business)
--    ↳ deal_authorizations → DELETED (all deals for that business)
--    ↳ processed_bills.business_id → SET NULL (bills keep history, lose business link)
-- 5. trusted_partner_bank_accounts → DELETED (their bank accounts)
-- 6. notifications → DELETED (their notifications via profile cascade)
-- 7. payments → DELETED (their payment records)
-- 8. subscriptions → DELETED (their subscription records)
--    ↳ subscription_renewals → DELETED (renewal history)
-- 9. user_qr_codes → DELETED (their QR codes)
--
-- This ensures complete cleanup of all trusted partner data when their
-- authentication account is removed.
-- =============================================================================
