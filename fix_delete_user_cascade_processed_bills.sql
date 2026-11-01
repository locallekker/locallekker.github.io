-- =====================================================
-- FIX: delete_user_cascade function - processed_bills column
-- =====================================================
-- The function was using user_id but processed_bills uses member_id
-- =====================================================

CREATE OR REPLACE FUNCTION delete_user_cascade()
RETURNS TRIGGER AS $$
BEGIN
    -- Delete in order of dependencies (child tables first)

    -- Delete virtual receipts (references deal_authorizations)
    DELETE FROM virtual_receipts
    WHERE deal_authorization_id IN (
        SELECT id FROM deal_authorizations WHERE member_id = OLD.id
    );

    -- Delete deal receipts (references deal_authorizations)
    DELETE FROM deal_receipts
    WHERE member_id = OLD.id;

    -- Delete notifications
    DELETE FROM notifications WHERE user_id = OLD.id;

    -- Delete deal authorizations (both member and trusted partner)
    DELETE FROM deal_authorizations
    WHERE member_id = OLD.id OR trusted_partner_id = OLD.id;

    -- Delete processed bills (FIXED: uses member_id, not user_id)
    DELETE FROM processed_bills WHERE member_id = OLD.id;

    -- Delete payments
    DELETE FROM payments WHERE user_id = OLD.id;

    -- Delete user QR codes
    DELETE FROM user_qr_codes WHERE user_id = OLD.id;

    -- Delete subscriptions
    DELETE FROM subscriptions WHERE user_id = OLD.id;

    -- Delete memberships
    DELETE FROM memberships WHERE user_id = OLD.id;

    -- Delete trusted partner bank accounts
    DELETE FROM trusted_partner_bank_accounts WHERE user_id = OLD.id;

    -- Delete businesses (this will cascade to related tables)
    DELETE FROM businesses WHERE owner_member_id = OLD.id;

    -- Delete trusted partners
    DELETE FROM trusted_partners WHERE user_id = OLD.id;

    -- Delete profile (should be last)
    DELETE FROM profiles WHERE id = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
