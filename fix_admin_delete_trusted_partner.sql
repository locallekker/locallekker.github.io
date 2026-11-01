-- Fix: admin_delete_trusted_partner function
-- Issue: Function uses IF v_tp_email IS NULL instead of IF NOT FOUND,
--        causing "Trusted partner not found" when profile exists but email is NULL
-- Also: Removes competing 1-param overload to avoid PostgREST ambiguity
-- Run this in Supabase SQL Editor

-- ============================================================================
-- STEP 0: Create archive tables IF they don't exist yet
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.archived_receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_receipt_id UUID,
    business_id UUID,
    business_name TEXT,
    trusted_partner_id UUID,
    trusted_partner_email TEXT,
    trusted_partner_name TEXT,
    image_url TEXT,
    bill_data JSONB,
    total_amount DECIMAL(10,2),
    discount_amount DECIMAL(10,2),
    parsed_data JSONB,
    deal_id UUID,
    deal_title TEXT,
    member_id UUID,
    member_email TEXT,
    original_created_at TIMESTAMP WITH TIME ZONE,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    archived_by UUID,
    deletion_reason TEXT,
    source_table TEXT
);

CREATE TABLE IF NOT EXISTS public.archived_paystack_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trusted_partner_id UUID,
    trusted_partner_email TEXT,
    paystack_auth_code TEXT,
    paystack_customer_code TEXT,
    paystack_payment_methods JSONB,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    archived_by UUID,
    deletion_reason TEXT
);

CREATE TABLE IF NOT EXISTS public.archived_pending_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_payment_id UUID,
    trusted_partner_id UUID,
    trusted_partner_email TEXT,
    trusted_partner_name TEXT,
    member_id UUID,
    member_email TEXT,
    amount DECIMAL(10,2),
    status TEXT,
    payment_method TEXT,
    plan_name TEXT,
    paystack_reference TEXT,
    transaction_id TEXT,
    original_created_at TIMESTAMP WITH TIME ZONE,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    archived_by UUID,
    deletion_reason TEXT,
    source_table TEXT
);

-- Enable RLS on archive tables
ALTER TABLE public.archived_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.archived_paystack_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.archived_pending_payments ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- STEP 1: Drop ALL overloads of admin_delete_trusted_partner
-- ============================================================================

DROP FUNCTION IF EXISTS public.admin_delete_trusted_partner(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.admin_delete_trusted_partner(UUID, TEXT) CASCADE;

-- ============================================================================
-- STEP 2: Create the fixed function (single version, no overloads)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_delete_trusted_partner(
    target_user_id UUID,
    deletion_reason TEXT DEFAULT 'Admin deletion'
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_id UUID;
    v_tp_email TEXT;
    v_tp_name TEXT;
    v_business_id UUID;
    v_profile_exists BOOLEAN := FALSE;
    v_receipts_archived INTEGER := 0;
    v_paystack_archived INTEGER := 0;
    v_payments_archived INTEGER := 0;
    v_deals_deleted INTEGER := 0;
    v_businesses_deleted INTEGER := 0;
    v_result JSONB;
BEGIN
    -- Get current user and verify they are admin
    v_admin_id := auth.uid();
    
    IF NOT EXISTS (
        SELECT 1 FROM memberships 
        WHERE user_id = v_admin_id AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Permission denied: Only admins can delete trusted partners';
    END IF;
    
    -- ====================================================================
    -- FIX: Use IF NOT FOUND instead of checking for NULL email
    -- This correctly handles profiles with NULL email columns
    -- ====================================================================
    SELECT email, name || ' ' || COALESCE(surname, ''), TRUE
    INTO v_tp_email, v_tp_name, v_profile_exists
    FROM profiles 
    WHERE id = target_user_id;
    
    IF NOT v_profile_exists THEN
        RAISE EXCEPTION 'Trusted partner not found: no profile with id %', target_user_id;
    END IF;

    -- Use email from auth.users as fallback if profiles.email is NULL
    IF v_tp_email IS NULL THEN
        SELECT email INTO v_tp_email FROM auth.users WHERE id = target_user_id;
    END IF;
    
    -- Get business ID if exists
    SELECT id INTO v_business_id
    FROM businesses
    WHERE owner_member_id = target_user_id
    LIMIT 1;
    
    -- ========================================================================
    -- Archive Paystack/Bank Data (safe: uses IF EXISTS pattern)
    -- ========================================================================
    BEGIN
        INSERT INTO archived_paystack_data (
            trusted_partner_id,
            trusted_partner_email,
            paystack_auth_code,
            paystack_customer_code,
            paystack_payment_methods,
            archived_by,
            deletion_reason
        )
        SELECT 
            target_user_id,
            COALESCE(v_tp_email, 'unknown'),
            paystack_auth_code,
            paystack_customer_code,
            paystack_payment_methods,
            v_admin_id,
            deletion_reason
        FROM profiles
        WHERE id = target_user_id
          AND (paystack_auth_code IS NOT NULL 
               OR paystack_customer_code IS NOT NULL 
               OR paystack_payment_methods IS NOT NULL);
        
        GET DIAGNOSTICS v_paystack_archived = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        v_paystack_archived := 0; -- Table or columns may not exist
    END;
    
    -- ========================================================================
    -- Archive Pending Payments
    -- ========================================================================
    BEGIN
        INSERT INTO archived_pending_payments (
            original_payment_id,
            trusted_partner_id,
            trusted_partner_email,
            trusted_partner_name,
            member_id,
            member_email,
            amount,
            status,
            payment_method,
            plan_name,
            paystack_reference,
            transaction_id,
            original_created_at,
            archived_by,
            deletion_reason,
            source_table
        )
        SELECT 
            p.id,
            target_user_id,
            COALESCE(v_tp_email, 'unknown'),
            COALESCE(v_tp_name, 'unknown'),
            p.user_id,
            pr.email,
            p.amount,
            p.status,
            p.payment_method,
            p.plan_name,
            p.paystack_reference,
            p.transaction_id,
            p.created_at,
            v_admin_id,
            deletion_reason,
            'payments'
        FROM payments p
        LEFT JOIN profiles pr ON pr.id = p.user_id
        WHERE p.user_id IN (
            SELECT owner_member_id FROM businesses WHERE owner_member_id = target_user_id
        )
        AND p.status IN ('pending', 'active', 'incomplete');
        
        GET DIAGNOSTICS v_payments_archived = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        v_payments_archived := 0;
    END;
    
    -- ========================================================================
    -- Delete pending payments for this TP's business
    -- ========================================================================
    BEGIN
        DELETE FROM payments 
        WHERE user_id IN (
            SELECT owner_member_id FROM businesses WHERE owner_member_id = target_user_id
        );
    EXCEPTION WHEN OTHERS THEN
        NULL; -- Ignore if table/column doesn't exist
    END;
    
    -- ========================================================================
    -- Archive receipts/bills (only if business exists)
    -- ========================================================================
    IF v_business_id IS NOT NULL THEN
        BEGIN
            INSERT INTO archived_receipts (
                original_receipt_id,
                business_id,
                business_name,
                trusted_partner_id,
                trusted_partner_email,
                trusted_partner_name,
                image_url,
                bill_data,
                total_amount,
                discount_amount,
                parsed_data,
                member_id,
                member_email,
                original_created_at,
                archived_by,
                deletion_reason,
                source_table
            )
            SELECT 
                pb.id,
                COALESCE(pb.business_id, tpd.business_id, pb.partner_id),
                b.name,
                target_user_id,
                COALESCE(v_tp_email, 'unknown'),
                COALESCE(v_tp_name, 'unknown'),
                pb.bill_url,
                pb.receipt_data,
                pb.original_total,
                pb.discount_amount,
                pb.receipt_data,
                pb.member_id,
                p.email,
                pb.created_at,
                v_admin_id,
                deletion_reason,
                'processed_bills'
            FROM processed_bills pb
            LEFT JOIN trusted_partner_discounts tpd ON tpd.id = pb.discount_id
            LEFT JOIN businesses b ON b.id = COALESCE(pb.business_id, tpd.business_id, pb.partner_id)
            LEFT JOIN profiles p ON p.id = pb.member_id
            WHERE (
                pb.business_id = v_business_id
                OR pb.partner_id = v_business_id
                OR tpd.business_id = v_business_id
            );
            
            GET DIAGNOSTICS v_receipts_archived = ROW_COUNT;
        EXCEPTION WHEN OTHERS THEN
            v_receipts_archived := 0;
        END;
    END IF;
    
    -- ========================================================================
    -- Delete all associated records (each in its own safe block)
    -- ========================================================================
    
    -- Delete virtual receipts
    IF v_business_id IS NOT NULL THEN
        BEGIN
            DELETE FROM virtual_receipts 
            WHERE deal_authorization_id IN (
                SELECT da.id FROM deal_authorizations da
                JOIN trusted_partner_discounts tpd ON tpd.id = da.discount_id
                WHERE tpd.business_id = v_business_id
            );
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;
    
    -- Delete deal authorizations
    IF v_business_id IS NOT NULL THEN
        BEGIN
            DELETE FROM deal_authorizations 
            WHERE discount_id IN (
                SELECT id FROM trusted_partner_discounts 
                WHERE business_id = v_business_id
            );
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;
    
    -- Delete deal images
    IF v_business_id IS NOT NULL THEN
        BEGIN
            DELETE FROM deal_images 
            WHERE deal_id IN (
                SELECT id FROM trusted_partner_discounts 
                WHERE business_id = v_business_id
            );
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;
    
    -- Delete deals/discounts
    IF v_business_id IS NOT NULL THEN
        BEGIN
            DELETE FROM trusted_partner_discounts 
            WHERE business_id = v_business_id;
            GET DIAGNOSTICS v_deals_deleted = ROW_COUNT;
        EXCEPTION WHEN OTHERS THEN 
            v_deals_deleted := 0;
        END;
    END IF;
    
    -- Delete processed bills
    IF v_business_id IS NOT NULL THEN
        BEGIN
            DELETE FROM processed_bills 
            WHERE business_id = v_business_id
                OR partner_id = v_business_id;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;
    
    -- Delete notifications
    BEGIN
        DELETE FROM notifications WHERE user_id = target_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    
    -- Delete QR codes
    BEGIN
        DELETE FROM user_qr_codes WHERE user_id = target_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    
    -- Delete subscriptions
    BEGIN
        DELETE FROM subscriptions WHERE user_id = target_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    
    -- Delete chat messages
    BEGIN
        DELETE FROM chat_messages WHERE sender_id = target_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    
    -- Delete chat participants
    BEGIN
        DELETE FROM chat_participants WHERE user_id = target_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    
    -- Delete paystack subaccounts
    BEGIN
        DELETE FROM paystack_subaccounts WHERE user_id = target_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    
    -- Delete partner bank accounts
    BEGIN
        DELETE FROM partner_bank_accounts WHERE user_id = target_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    
    -- Delete trusted_partners record
    BEGIN
        DELETE FROM trusted_partners WHERE user_id = target_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    
    -- Delete business
    BEGIN
        DELETE FROM businesses WHERE owner_member_id = target_user_id;
        GET DIAGNOSTICS v_businesses_deleted = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN 
        v_businesses_deleted := 0;
    END;
    
    -- Clear Paystack fields from profile before deletion
    BEGIN
        UPDATE profiles 
        SET paystack_auth_code = NULL,
            paystack_customer_code = NULL,
            paystack_payment_methods = NULL
        WHERE id = target_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    
    -- Delete membership
    BEGIN
        DELETE FROM memberships WHERE user_id = target_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    
    -- Delete profile
    DELETE FROM profiles WHERE id = target_user_id;
    
    -- Delete from auth.users (SECURITY DEFINER allows this)
    BEGIN
        DELETE FROM auth.users WHERE id = target_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    
    -- ========================================================================
    -- Return summary
    -- ========================================================================
    v_result := jsonb_build_object(
        'success', true,
        'trusted_partner_id', target_user_id,
        'trusted_partner_email', COALESCE(v_tp_email, 'unknown'),
        'receipts_archived', v_receipts_archived,
        'paystack_data_archived', v_paystack_archived,
        'pending_payments_archived', v_payments_archived,
        'deals_deleted', v_deals_deleted,
        'businesses_deleted', v_businesses_deleted,
        'archived_by', v_admin_id,
        'deletion_reason', deletion_reason,
        'deleted_at', NOW(),
        'message', 'Trusted partner completely deleted'
    );
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error deleting trusted partner: %', SQLERRM;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.admin_delete_trusted_partner(UUID, TEXT) TO authenticated;

-- ============================================================================
-- STEP 3: Verify
-- ============================================================================
SELECT 
    proname, 
    pronargs,
    pg_get_function_arguments(oid) as args
FROM pg_proc 
WHERE proname = 'admin_delete_trusted_partner'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
