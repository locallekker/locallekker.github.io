-- =====================================================
-- UPDATE ADMIN DELETE MEMBER FUNCTION
-- Deactivates member (sets is_deactivated = true) so signup can autofill
-- This uses the same deactivation logic as member self-deactivation
-- =====================================================

CREATE OR REPLACE FUNCTION admin_delete_member_data(member_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSONB;
  member_email TEXT;
  member_name TEXT;
  col_name TEXT;
  sql TEXT;
BEGIN
  -- Verify the user is a member and get their details
  SELECT email, name 
  INTO member_email, member_name
  FROM profiles
  WHERE id = member_user_id AND role = 'member';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % is not a member or does not exist', member_user_id;
  END IF;

  result := jsonb_build_object(
    'member_id', member_user_id,
    'email', member_email,
    'name', member_name,
    'action', 'deactivated'
  );

  -- Mark profile as deactivated (keeps profile data for signup autofill)
  UPDATE profiles 
  SET 
    is_deactivated = true,
    deactivated_at = NOW(),
    deactivation_reason = 'Admin deletion',
    updated_at = NOW()
  WHERE id = member_user_id;
  
  result := result || jsonb_build_object('profile_deactivated', true);

  -- Deactivate all QR codes
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_qr_codes') THEN
    UPDATE user_qr_codes 
    SET is_active = false 
    WHERE user_id = member_user_id AND is_active = true;
    result := result || jsonb_build_object('qr_codes_deactivated', true);
  END IF;

  -- Update subscription status to deactivated
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='subscriptions') THEN
    UPDATE subscriptions 
    SET status = 'deactivated', updated_at = NOW()
    WHERE user_id = member_user_id AND status != 'deactivated';
    result := result || jsonb_build_object('subscription_deactivated', true);
  END IF;

  -- Delete member_receipts (cleanup)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='member_receipts' AND column_name='member_id') THEN
    EXECUTE 'DELETE FROM member_receipts WHERE member_id = $1' USING member_user_id;
    result := result || jsonb_build_object('member_receipts_deleted', true);
  END IF;

  -- Delete deal_authorizations (cleanup)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='deal_authorizations' AND column_name='member_id') THEN
    EXECUTE 'DELETE FROM deal_authorizations WHERE member_id = $1' USING member_user_id;
    result := result || jsonb_build_object('deal_authorizations_deleted', true);
  END IF;

  -- Delete payments (cleanup)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='payments') THEN
    DELETE FROM payments WHERE user_id = member_user_id;
    result := result || jsonb_build_object('payments_deleted', true);
  END IF;

  -- Delete notifications (cleanup)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='notifications') THEN
    DELETE FROM notifications WHERE user_id = member_user_id;
    result := result || jsonb_build_object('notifications_deleted', true);
  END IF;

  RETURN result::json;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to deactivate member: %', SQLERRM;
END;
$$;

-- Grant execute permission to authenticated users (admin check in app layer)
GRANT EXECUTE ON FUNCTION admin_delete_member_data(UUID) TO authenticated;

-- Keep old function for backward compatibility but mark as deprecated
CREATE OR REPLACE FUNCTION admin_delete_member(member_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE NOTICE 'admin_delete_member is deprecated. Use admin_delete_member_data and Supabase Admin API';
  RETURN admin_delete_member_data(member_user_id);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_member(UUID) TO authenticated;
