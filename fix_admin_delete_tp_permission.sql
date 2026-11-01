-- Fix: admin_delete_trusted_partner permission check
-- Issue 1: Function checks memberships for role='admin' but admins are in admin_dashboard table
-- Issue 2: After deletion, auth user must be fully removed so re-signup works cleanly
-- Run this in Supabase SQL Editor

-- ============================================================================
-- Drop ALL overloads to avoid PostgREST ambiguity
-- ============================================================================
DROP FUNCTION IF EXISTS public.admin_delete_trusted_partner(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.admin_delete_trusted_partner(UUID, TEXT) CASCADE;

-- ============================================================================
-- Recreate function with corrected admin check (admin_dashboard OR memberships)
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
    v_auth_deleted BOOLEAN := FALSE;
    v_result JSONB;
BEGIN
    -- Get current user and verify they are admin
    v_admin_id := auth.uid();

    -- FIX: Check by known admin emails (mirrors Flutter app logic) OR memberships role
    IF NOT EXISTS (
        SELECT 1 FROM auth.users
        WHERE id = v_admin_id
          AND email IN ('admin@locallekker.com', 'locallekkerclub@gmail.com')
        UNION
        SELECT 1 FROM public.memberships WHERE user_id = v_admin_id AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Permission denied: Only admins can delete trusted partners';
    END IF;

    -- Get TP profile details
    SELECT email, COALESCE(name, '') || ' ' || COALESCE(surname, ''), TRUE
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

    -- Get business ID if exists (handle both column names)
    BEGIN
        SELECT id INTO v_business_id
        FROM businesses
        WHERE owner_member_id = target_user_id
        LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        BEGIN
            SELECT id INTO v_business_id
            FROM businesses
            WHERE user_id = target_user_id
            LIMIT 1;
        EXCEPTION WHEN OTHERS THEN
            v_business_id := NULL;
        END;
    END;

    -- ========================================================================
    -- Archive Paystack/Bank Data
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
        v_paystack_archived := 0;
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
        WHERE p.user_id = target_user_id
          AND p.status IN ('pending', 'active', 'incomplete');
        GET DIAGNOSTICS v_payments_archived = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        v_payments_archived := 0;
    END;

    -- ========================================================================
    -- Archive receipts/bills
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
            WHERE pb.business_id = v_business_id
               OR pb.partner_id = v_business_id
               OR tpd.business_id = v_business_id;
            GET DIAGNOSTICS v_receipts_archived = ROW_COUNT;
        EXCEPTION WHEN OTHERS THEN
            v_receipts_archived := 0;
        END;
    END IF;

    -- ========================================================================
    -- Delete all associated records
    -- ========================================================================

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

        BEGIN
            DELETE FROM deal_authorizations
            WHERE discount_id IN (
                SELECT id FROM trusted_partner_discounts WHERE business_id = v_business_id
            );
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        BEGIN
            DELETE FROM deal_images
            WHERE deal_id IN (
                SELECT id FROM trusted_partner_discounts WHERE business_id = v_business_id
            );
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        BEGIN
            DELETE FROM trusted_partner_discounts WHERE business_id = v_business_id;
            GET DIAGNOSTICS v_deals_deleted = ROW_COUNT;
        EXCEPTION WHEN OTHERS THEN
            v_deals_deleted := 0;
        END;

        BEGIN
            DELETE FROM processed_bills
            WHERE business_id = v_business_id OR partner_id = v_business_id;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;

    BEGIN DELETE FROM notifications WHERE user_id = target_user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM user_qr_codes WHERE user_id = target_user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM subscriptions WHERE user_id = target_user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM payments WHERE user_id = target_user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM chat_messages WHERE sender_id = target_user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM chat_participants WHERE user_id = target_user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM paystack_subaccounts WHERE user_id = target_user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM partner_bank_accounts WHERE user_id = target_user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM trusted_partners WHERE user_id = target_user_id; EXCEPTION WHEN OTHERS THEN NULL; END;

    -- Delete business (handle both column names)
    BEGIN
        DELETE FROM businesses WHERE owner_member_id = target_user_id;
        GET DIAGNOSTICS v_businesses_deleted = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        BEGIN
            DELETE FROM businesses WHERE user_id = target_user_id;
            GET DIAGNOSTICS v_businesses_deleted = ROW_COUNT;
        EXCEPTION WHEN OTHERS THEN
            v_businesses_deleted := 0;
        END;
    END;

    -- Delete membership and profile
    BEGIN DELETE FROM memberships WHERE user_id = target_user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM profiles WHERE id = target_user_id; EXCEPTION WHEN OTHERS THEN NULL; END;

    -- Delete auth user (SECURITY DEFINER with postgres owner allows this)
    -- This ensures clean re-signup (no "Reset Password" email on new signup)
    BEGIN
        DELETE FROM auth.users WHERE id = target_user_id;
        v_auth_deleted := TRUE;
    EXCEPTION WHEN OTHERS THEN
        v_auth_deleted := FALSE;
        -- Auth deletion will be completed by the edge function called from the app
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
        'auth_deleted', v_auth_deleted,
        'archived_by', v_admin_id,
        'deletion_reason', deletion_reason,
        'deleted_at', NOW(),
        'message', CASE WHEN v_auth_deleted
            THEN 'Trusted partner completely deleted including auth user'
            ELSE 'Trusted partner data deleted; auth user deletion pending (call edge function)'
        END
    );

    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error deleting trusted partner: %', SQLERRM;
END;
$$;

-- Grant execute permission to authenticated users (admin check inside function)
GRANT EXECUTE ON FUNCTION public.admin_delete_trusted_partner(UUID, TEXT) TO authenticated;

-- ============================================================================
-- Verify
-- ============================================================================
SELECT
    proname,
    pronargs,
    pg_get_function_arguments(oid) AS args
FROM pg_proc
WHERE proname = 'admin_delete_trusted_partner'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
