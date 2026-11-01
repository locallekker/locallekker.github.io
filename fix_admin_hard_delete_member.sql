-- =====================================================
-- FIX: Admin Hard Delete Member - Complete Removal
-- =====================================================
-- When admin permanently deletes a deactivated member,
-- remove ALL data from ALL tables + auth.users
-- Auth user deletion is handled via Edge Function in Dart layer
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
BEGIN
  -- Verify the user exists in profiles (allow already-deactivated members)
  SELECT email, name 
  INTO member_email, member_name
  FROM profiles
  WHERE id = member_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % does not exist in profiles', member_user_id;
  END IF;

  result := jsonb_build_object(
    'member_id', member_user_id,
    'email', member_email,
    'name', member_name,
    'action', 'hard_deleted'
  );

  -- 1. Delete member_receipts
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='member_receipts' AND column_name='member_id') THEN
    DELETE FROM member_receipts WHERE member_id = member_user_id;
    result := result || jsonb_build_object('member_receipts_deleted', true);
  END IF;

  -- 2. Delete deal_authorizations
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='deal_authorizations' AND column_name='member_id') THEN
    DELETE FROM deal_authorizations WHERE member_id = member_user_id;
    result := result || jsonb_build_object('deal_authorizations_deleted', true);
  END IF;

  -- 3. Delete processed_bills (member's scanned bills)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='processed_bills' AND column_name='member_id') THEN
    DELETE FROM processed_bills WHERE member_id = member_user_id;
    result := result || jsonb_build_object('processed_bills_deleted', true);
  END IF;

  -- 4. Delete user_qr_codes
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_qr_codes') THEN
    DELETE FROM user_qr_codes WHERE user_id = member_user_id;
    result := result || jsonb_build_object('qr_codes_deleted', true);
  END IF;

  -- 5. Delete subscription_renewals
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='subscription_renewals') THEN
    DELETE FROM subscription_renewals WHERE user_id = member_user_id;
    result := result || jsonb_build_object('subscription_renewals_deleted', true);
  END IF;

  -- 6. Delete subscriptions
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='subscriptions') THEN
    DELETE FROM subscriptions WHERE user_id = member_user_id;
    result := result || jsonb_build_object('subscriptions_deleted', true);
  END IF;

  -- 7. Delete payments
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='payments') THEN
    DELETE FROM payments WHERE user_id = member_user_id;
    result := result || jsonb_build_object('payments_deleted', true);
  END IF;

  -- 8. Delete notifications
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='notifications') THEN
    DELETE FROM notifications WHERE user_id = member_user_id;
    result := result || jsonb_build_object('notifications_deleted', true);
  END IF;

  -- 9. Delete chat_messages
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='chat_messages') THEN
    DELETE FROM chat_messages WHERE sender_id = member_user_id;
    result := result || jsonb_build_object('chat_messages_deleted', true);
  END IF;

  -- 10. Delete members_card_details (saved payment methods)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='members_card_details') THEN
    DELETE FROM members_card_details WHERE user_id = member_user_id;
    result := result || jsonb_build_object('card_details_deleted', true);
  END IF;

  -- 11. Delete memberships
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='memberships') THEN
    DELETE FROM memberships WHERE user_id = member_user_id;
    result := result || jsonb_build_object('memberships_deleted', true);
  END IF;

  -- 12. Delete chat_read_receipts
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='chat_read_receipts') THEN
    DELETE FROM chat_read_receipts WHERE user_id = member_user_id;
    result := result || jsonb_build_object('chat_read_receipts_deleted', true);
  END IF;

  -- 13. Finally, DELETE the profile (hard delete, not deactivate)
  DELETE FROM profiles WHERE id = member_user_id;
  result := result || jsonb_build_object('profile_deleted', true);

  -- NOTE: auth.users deletion is handled via Edge Function in the Dart app layer
  -- The SQL function cannot reliably delete from auth.users

  RETURN result::json;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to hard-delete member: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_member_data(UUID) TO authenticated;

-- Keep backward compat wrapper
CREATE OR REPLACE FUNCTION admin_delete_member(member_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN admin_delete_member_data(member_user_id);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_member(UUID) TO authenticated;

-- =====================================================
-- VERIFICATION: Run after deployment
-- =====================================================
-- SELECT admin_delete_member_data('test-uuid-here'::uuid);
-- Then verify with:
-- SELECT * FROM profiles WHERE id = 'test-uuid-here';
-- SELECT * FROM subscriptions WHERE user_id = 'test-uuid-here';
-- SELECT * FROM user_qr_codes WHERE user_id = 'test-uuid-here';
