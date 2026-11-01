-- Complete Trusted Partner Deletion System
-- This creates archive tables and a function to completely delete a trusted partner
-- Run this in Supabase SQL Editor

-- ============================================================================
-- STEP 1: Create Archive Tables
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.archived_receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Original receipt data
    original_receipt_id UUID,
    business_id UUID,
    business_name TEXT,
    trusted_partner_id UUID,
    trusted_partner_email TEXT,
    trusted_partner_name TEXT,
    
    -- Receipt details
    image_url TEXT,
    bill_data JSONB,
    total_amount DECIMAL(10,2),
    discount_amount DECIMAL(10,2),
    parsed_data JSONB,
    
    -- Deal information if applicable
    deal_id UUID,
    deal_title TEXT,
    
    -- Member information if applicable
    member_id UUID,
    member_email TEXT,
    
    -- Metadata
    original_created_at TIMESTAMP WITH TIME ZONE,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    archived_by UUID, -- Admin who performed the deletion
    deletion_reason TEXT,
    
    -- Original table source
    source_table TEXT -- 'processed_bills' or other
);

-- Archive table for Paystack/payment information
CREATE TABLE IF NOT EXISTS public.archived_paystack_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Trusted partner reference
    trusted_partner_id UUID,
    trusted_partner_email TEXT,
    
    -- Paystack fields (actual columns in profiles table)
    paystack_auth_code TEXT,
    paystack_customer_code TEXT,
    paystack_payment_methods JSONB,
    
    -- Metadata
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    archived_by UUID,
    deletion_reason TEXT
);

DROP TABLE IF EXISTS public.archived_pending_payments CASCADE;

-- Archive table for pending payments
CREATE TABLE IF NOT EXISTS public.archived_pending_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Payment reference
    original_payment_id UUID,
    trusted_partner_id UUID,
    trusted_partner_email TEXT,
    trusted_partner_name TEXT,
    
    -- Payment details
    member_id UUID,
    member_email TEXT,
    amount DECIMAL(10,2),
    status TEXT,
    payment_method TEXT,
    plan_name TEXT,
    
    -- Paystack reference
    paystack_reference TEXT,
    transaction_id TEXT,
    
    -- Metadata
    original_created_at TIMESTAMP WITH TIME ZONE,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    archived_by UUID,
    deletion_reason TEXT,
    
    -- Original table source
    source_table TEXT
);

-- Add indexes for quick lookups
CREATE INDEX IF NOT EXISTS idx_archived_receipts_tp_id ON public.archived_receipts(trusted_partner_id);
CREATE INDEX IF NOT EXISTS idx_archived_receipts_business_id ON public.archived_receipts(business_id);
CREATE INDEX IF NOT EXISTS idx_archived_receipts_archived_at ON public.archived_receipts(archived_at);

CREATE INDEX IF NOT EXISTS idx_archived_paystack_tp_id ON public.archived_paystack_data(trusted_partner_id);
CREATE INDEX IF NOT EXISTS idx_archived_paystack_archived_at ON public.archived_paystack_data(archived_at);

CREATE INDEX IF NOT EXISTS idx_archived_payments_tp_id ON public.archived_pending_payments(trusted_partner_id);
CREATE INDEX IF NOT EXISTS idx_archived_payments_member_id ON public.archived_pending_payments(member_id);
CREATE INDEX IF NOT EXISTS idx_archived_payments_archived_at ON public.archived_pending_payments(archived_at);

-- Enable RLS on all archive tables
ALTER TABLE public.archived_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.archived_paystack_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.archived_pending_payments ENABLE ROW LEVEL SECURITY;

-- Allow admin to view and manage archived data
DROP POLICY IF EXISTS "Admins can view archived receipts" ON public.archived_receipts;
CREATE POLICY "Admins can view archived receipts"
ON public.archived_receipts FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM memberships 
        WHERE user_id = auth.uid() AND role = 'admin'
    )
);

DROP POLICY IF EXISTS "Admins can insert archived receipts" ON public.archived_receipts;
CREATE POLICY "Admins can insert archived receipts"
ON public.archived_receipts FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM memberships 
        WHERE user_id = auth.uid() AND role = 'admin'
    )
);

DROP POLICY IF EXISTS "Admins can view archived paystack" ON public.archived_paystack_data;
CREATE POLICY "Admins can view archived paystack"
ON public.archived_paystack_data FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM memberships 
        WHERE user_id = auth.uid() AND role = 'admin'
    )
);

DROP POLICY IF EXISTS "Admins can insert archived paystack" ON public.archived_paystack_data;
CREATE POLICY "Admins can insert archived paystack"
ON public.archived_paystack_data FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM memberships 
        WHERE user_id = auth.uid() AND role = 'admin'
    )
);

DROP POLICY IF EXISTS "Admins can view archived payments" ON public.archived_pending_payments;
CREATE POLICY "Admins can view archived payments"
ON public.archived_pending_payments FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM memberships 
        WHERE user_id = auth.uid() AND role = 'admin'
    )
);

DROP POLICY IF EXISTS "Admins can insert archived payments" ON public.archived_pending_payments;
CREATE POLICY "Admins can insert archived payments"
ON public.archived_pending_payments FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM memberships 
        WHERE user_id = auth.uid() AND role = 'admin'
    )
);

-- ============================================================================
-- STEP 2: Create Function to Completely Delete Trusted Partner
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
    
    -- Get trusted partner details
    SELECT email, name || ' ' || COALESCE(surname, '') 
    INTO v_tp_email, v_tp_name
    FROM profiles 
    WHERE id = target_user_id;
    
    IF v_tp_email IS NULL THEN
        RAISE EXCEPTION 'Trusted partner not found';
    END IF;
    
    -- Get business ID if exists
    SELECT id INTO v_business_id
    FROM businesses
    WHERE owner_member_id = target_user_id
    LIMIT 1;
    
    -- ========================================================================
    -- Archive Paystack/Bank Data
    -- ========================================================================
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
        v_tp_email,
        paystack_auth_code,
        paystack_customer_code,
        paystack_payment_methods,
        v_admin_id,
        deletion_reason
    FROM profiles
    WHERE id = target_user_id;
    
    GET DIAGNOSTICS v_paystack_archived = ROW_COUNT;
    
    -- ========================================================================
    -- Archive Pending Payments (so members are notified of TP termination)
    -- ========================================================================
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
        v_tp_email,
        v_tp_name,
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
    
    -- ========================================================================
    -- Delete all pending payments for this TP's business
    -- ========================================================================
    DELETE FROM payments 
    WHERE user_id IN (
        SELECT owner_member_id FROM businesses WHERE owner_member_id = target_user_id
    );
    
    -- ========================================================================
    -- Archive all receipts/bills associated with this trusted partner
    -- ========================================================================
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
        v_tp_email,
        v_tp_name,
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
    
    -- ========================================================================
    -- Delete all associated records
    -- ========================================================================
    
    -- Delete virtual receipts (references deal_authorizations)
    DELETE FROM virtual_receipts 
    WHERE deal_authorization_id IN (
        SELECT da.id FROM deal_authorizations da
        JOIN trusted_partner_discounts tpd ON tpd.id = da.discount_id
        WHERE tpd.business_id = v_business_id
    );
    
    -- Delete deal authorizations
    DELETE FROM deal_authorizations 
    WHERE discount_id IN (
        SELECT id FROM trusted_partner_discounts 
        WHERE business_id = v_business_id
    );
    
    -- Delete deals/discounts
    DELETE FROM trusted_partner_discounts 
    WHERE business_id = v_business_id;
    
    GET DIAGNOSTICS v_deals_deleted = ROW_COUNT;
    
    -- Delete processed bills
     DELETE FROM processed_bills 
     WHERE business_id = v_business_id
         OR partner_id = v_business_id
         OR discount_id IN (SELECT id FROM trusted_partner_discounts WHERE business_id = v_business_id);
    
    -- Delete notifications for this user
    DELETE FROM notifications WHERE user_id = target_user_id;
    
    -- Delete QR codes
    DELETE FROM user_qr_codes WHERE user_id = target_user_id;
    
    -- Delete subscriptions
    DELETE FROM subscriptions WHERE user_id = target_user_id;
    
    -- Delete business
    DELETE FROM businesses WHERE owner_member_id = target_user_id;
    
    GET DIAGNOSTICS v_businesses_deleted = ROW_COUNT;
    
    -- Clear Paystack fields
    UPDATE profiles 
    SET 
        paystack_auth_code = NULL,
        paystack_customer_code = NULL,
        paystack_payment_methods = NULL
    WHERE id = target_user_id;
    
    -- Delete membership
    DELETE FROM memberships WHERE user_id = target_user_id;
    
    -- Delete profile
    DELETE FROM profiles WHERE id = target_user_id;
    
    -- ========================================================================
    -- Delete from auth.users (Supabase Auth table)
    -- ========================================================================
    DELETE FROM auth.users WHERE id = target_user_id;
    
    -- ========================================================================
    -- Return summary
    -- ========================================================================
    v_result := jsonb_build_object(
        'success', true,
        'trusted_partner_id', target_user_id,
        'trusted_partner_email', v_tp_email,
        'receipts_archived', v_receipts_archived,
        'paystack_data_archived', v_paystack_archived,
        'pending_payments_archived', v_payments_archived,
        'pending_payments_deleted', v_payments_archived,
        'deals_deleted', v_deals_deleted,
        'businesses_deleted', v_businesses_deleted,
        'archived_by', v_admin_id,
        'deletion_reason', deletion_reason,
        'deleted_at', NOW(),
        'auth_deletion_required', true,
        'message', 'Trusted partner completely deleted: database cleaned, Paystack/payment data archived, auth user deletion required'
    );
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error deleting trusted partner: %', SQLERRM;
END;
$$;

-- Grant execute permission to authenticated users (function checks admin internally)
GRANT EXECUTE ON FUNCTION public.admin_delete_trusted_partner(UUID, TEXT) TO authenticated;

-- ============================================================================
-- STEP 3: Test the setup
-- ============================================================================

-- Verify archive tables exist
SELECT 
    'Archive tables created' as status,
    COUNT(*) as archive_tables
FROM information_schema.tables
WHERE table_schema = 'public' 
  AND table_name IN ('archived_receipts', 'archived_paystack_data', 'archived_pending_payments');

-- Verify function exists
SELECT 
    'Delete function created' as status,
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'admin_delete_trusted_partner';

-- Show sample usage (DO NOT RUN - just for reference)
/*
-- To delete a trusted partner, call this function with their UUID:
SELECT admin_delete_trusted_partner(
    'TRUSTED_PARTNER_USER_ID_HERE'::UUID,
    'Violation of terms and conditions'
);

-- Response will be JSON like:
{
  "success": true,
  "trusted_partner_id": "...",
  "trusted_partner_email": "...",
  "receipts_archived": 42,
  "paystack_data_archived": 1,
  "pending_payments_archived": 5,
  "pending_payments_deleted": 5,
  "deals_deleted": 8,
  "businesses_deleted": 1,
  "archived_by": "...",
  "deletion_reason": "Violation of terms and conditions",
  "deleted_at": "2026-01-06T...",
  "auth_deletion_required": true,
  "message": "Trusted partner completely deleted: database cleaned, Paystack/payment data archived, auth user deletion required"
}
*/

-- ============================================================================
-- STEP 3: Test the setup
-- ============================================================================

-- Verify archive table exists
SELECT 
    'Archive table created' as status,
    COUNT(*) as column_count
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'archived_receipts';

-- Verify function exists
SELECT 
    'Delete function created' as status,
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'admin_delete_trusted_partner';

-- Show sample usage (DO NOT RUN - just for reference)
/*
-- To delete a trusted partner:
SELECT admin_delete_trusted_partner(
    'TRUSTED_PARTNER_USER_ID_HERE'::UUID,
    'Violation of terms and conditions'
);
*/
