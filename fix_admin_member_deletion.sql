-- =====================================================
-- FIX: Admin Member and Trusted Partner Deletion
-- =====================================================
-- Problem: Users are deleted from UI but remain in auth.users
-- Cause: SQL functions cannot delete from auth.users due to RLS
-- Solution: Split deletion into two steps:
--   1. Delete all related data via SQL function
--   2. Delete auth user via Supabase Admin API
-- =====================================================

-- =====================================================
-- MEMBER DELETION FIX
-- =====================================================

-- Create new function that only deletes member data (not auth.users)
CREATE OR REPLACE FUNCTION admin_delete_member_data(member_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  member_email TEXT;
  member_name TEXT;
BEGIN
  -- Verify the user is a member
  SELECT email, name INTO member_email, member_name
  FROM profiles
  WHERE id = member_user_id AND role = 'member';
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % is not a member or does not exist', member_user_id;
  END IF;

  -- 1. Delete member's copy of receipts (member_receipts table)
  DELETE FROM member_receipts WHERE member_id = member_user_id;

  -- 2. Delete deal authorizations (requests made by member)
  -- TP receipts (virtual_receipts, deal_receipts) remain for audit
  DELETE FROM deal_authorizations WHERE member_id = member_user_id;

  -- 3. Delete QR codes
  DELETE FROM user_qr_codes WHERE user_id = member_user_id;

  -- 4. Delete subscriptions
  DELETE FROM subscriptions WHERE user_id = member_user_id;

  -- 5. Delete payments
  DELETE FROM payments WHERE user_id = member_user_id;

  -- 6. Delete notifications
  DELETE FROM notifications WHERE user_id = member_user_id;

  -- 7. Delete membership records
  DELETE FROM memberships WHERE user_id = member_user_id;

  -- 8. Delete profile
  DELETE FROM profiles WHERE id = member_user_id;

  -- NOTE: auth.users deletion must be done via Supabase Admin API
  -- This is handled in the Dart/Flutter app layer

  RETURN json_build_object(
    'success', true,
    'member_id', member_user_id,
    'email', member_email,
    'name', member_name,
    'message', 'Member data deleted successfully. Auth user must be deleted via Admin API.'
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to delete member data: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_member_data(UUID) TO authenticated;

-- Update old function to use new one (for backward compatibility)
CREATE OR REPLACE FUNCTION admin_delete_member(member_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE NOTICE 'admin_delete_member is deprecated. Use admin_delete_member_data + Supabase Admin API';
  RETURN admin_delete_member_data(member_user_id);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_member(UUID) TO authenticated;

-- =====================================================
-- TRUSTED PARTNER DELETION FIX
-- =====================================================

-- Create new function that only deletes trusted partner data (not auth.users)
CREATE OR REPLACE FUNCTION admin_delete_trusted_partner_data(tp_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  tp_email TEXT;
  tp_name TEXT;
  business_ids UUID[];
  deal_ids UUID[];
BEGIN
  -- Verify the user is a trusted partner
  SELECT email, name INTO tp_email, tp_name
  FROM profiles
  WHERE id = tp_user_id AND role = 'trusted_partner';
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % is not a trusted partner or does not exist', tp_user_id;
  END IF;

  -- Get all business IDs for this TP
  SELECT array_agg(id) INTO business_ids
  FROM businesses
  WHERE user_id = tp_user_id;

  -- Get all deal IDs for these businesses
  IF business_ids IS NOT NULL THEN
    SELECT array_agg(id) INTO deal_ids
    FROM trusted_partner_discounts
    WHERE business_id = ANY(business_ids);
  END IF;

  -- 1. Delete deal receipts (TP's receipt records)
  IF deal_ids IS NOT NULL THEN
    DELETE FROM deal_receipts WHERE deal_id = ANY(deal_ids);
  END IF;

  -- 2. Delete virtual receipts
  IF deal_ids IS NOT NULL THEN
    DELETE FROM virtual_receipts WHERE deal_id = ANY(deal_ids);
  END IF;

  -- 3. Delete member receipts that reference these deals
  IF deal_ids IS NOT NULL THEN
    DELETE FROM member_receipts WHERE deal_id = ANY(deal_ids);
  END IF;

  -- 4. Delete deal authorizations
  IF deal_ids IS NOT NULL THEN
    DELETE FROM deal_authorizations WHERE deal_id = ANY(deal_ids);
  END IF;

  -- 5. Delete deal images
  IF deal_ids IS NOT NULL THEN
    DELETE FROM deal_images WHERE deal_id = ANY(deal_ids);
  END IF;

  -- 6. Delete deals (trusted_partner_discounts)
  IF deal_ids IS NOT NULL THEN
    DELETE FROM trusted_partner_discounts WHERE id = ANY(deal_ids);
  END IF;

  -- 7. Delete processed bills
  IF business_ids IS NOT NULL THEN
    DELETE FROM processed_bills WHERE business_id = ANY(business_ids);
  END IF;

  -- 8. Delete businesses
  DELETE FROM businesses WHERE user_id = tp_user_id;

  -- 9. Delete trusted partner record
  DELETE FROM trusted_partners WHERE user_id = tp_user_id;

  -- 10. Delete paystack subaccounts
  DELETE FROM paystack_subaccounts WHERE user_id = tp_user_id;

  -- 11. Delete bank accounts
  DELETE FROM partner_bank_accounts WHERE user_id = tp_user_id;

  -- 12. Delete QR codes
  DELETE FROM user_qr_codes WHERE user_id = tp_user_id;

  -- 13. Delete payments
  DELETE FROM payments WHERE user_id = tp_user_id;

  -- 14. Delete notifications
  DELETE FROM notifications WHERE user_id = tp_user_id;

  -- 15. Delete membership records
  DELETE FROM memberships WHERE user_id = tp_user_id;

  -- 16. Delete profile
  DELETE FROM profiles WHERE id = tp_user_id;

  -- NOTE: auth.users deletion must be done via Supabase Admin API
  -- This is handled in the Dart/Flutter app layer

  RETURN json_build_object(
    'success', true,
    'tp_user_id', tp_user_id,
    'email', tp_email,
    'name', tp_name,
    'business_count', COALESCE(array_length(business_ids, 1), 0),
    'deal_count', COALESCE(array_length(deal_ids, 1), 0),
    'message', 'Trusted partner data deleted successfully. Auth user must be deleted via Admin API.'
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to delete trusted partner data: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_trusted_partner_data(UUID) TO authenticated;

-- Update old function to use new one (for backward compatibility)
CREATE OR REPLACE FUNCTION admin_delete_trusted_partner(tp_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE NOTICE 'admin_delete_trusted_partner is deprecated. Use admin_delete_trusted_partner_data + Supabase Admin API';
  RETURN admin_delete_trusted_partner_data(tp_user_id);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_trusted_partner(UUID) TO authenticated;

-- =====================================================
-- USAGE NOTES
-- =====================================================
-- In your Dart/Flutter app:
-- 1. Call admin_delete_member_data(user_id) or admin_delete_trusted_partner_data(user_id)
-- 2. Call supabase.auth.admin.deleteUser(user_id) to delete from auth.users
-- 
-- This two-step process ensures complete deletion while respecting
-- Supabase's security model for auth.users management
-- =====================================================
