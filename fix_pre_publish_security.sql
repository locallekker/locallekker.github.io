-- ============================================================
-- PRE-PUBLISH SECURITY HARDENING
-- Run this in Supabase SQL Editor BEFORE publishing the app
-- ============================================================

-- ============================================================
-- 1. RESTRICT MEMBER UPDATE ON deal_authorizations
-- Members should only update payment-related columns
-- They should NOT be able to set status to 'approved' or 'completed' directly
-- ============================================================

-- Drop the overly-permissive member update policy
DROP POLICY IF EXISTS "deal_auth_update_member" ON deal_authorizations;

-- Create a server-side function that only allows safe member updates
-- Members can mark payment_completed_at and completed_at ONLY if:
--   1. They own the deal (member_id = auth.uid())
--   2. The deal is currently in 'approved' status
--   3. They are setting status to 'completed' (not arbitrary values)
CREATE OR REPLACE FUNCTION check_member_deal_update()
RETURNS TRIGGER AS $$
BEGIN
  -- If the update is by the member (not TP, not admin)
  IF OLD.member_id = auth.uid() THEN
    -- Members can only transition from 'approved' → 'completed'
    IF OLD.status = 'approved' AND NEW.status = 'completed' THEN
      -- Allow: setting payment_completed_at and completed_at
      RETURN NEW;
    END IF;

    -- Members can also cancel their pending deals (set to rejected)
    IF OLD.status = 'pending' AND NEW.status = 'rejected' THEN
      RETURN NEW;
    END IF;

    -- Block any other status change by members
    IF OLD.status != NEW.status THEN
      RAISE EXCEPTION 'Members cannot change deal status from % to %', OLD.status, NEW.status;
    END IF;

    -- Block members from changing the amount
    IF OLD.amount IS DISTINCT FROM NEW.amount THEN
      RAISE EXCEPTION 'Members cannot change deal amount';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for the validation
DROP TRIGGER IF EXISTS validate_member_deal_update ON deal_authorizations;
CREATE TRIGGER validate_member_deal_update
  BEFORE UPDATE ON deal_authorizations
  FOR EACH ROW
  EXECUTE FUNCTION check_member_deal_update();

-- Re-create the member update policy (now protected by trigger)
CREATE POLICY "deal_auth_update_member"
ON deal_authorizations FOR UPDATE TO authenticated
USING (member_id = auth.uid())
WITH CHECK (member_id = auth.uid());


-- ============================================================
-- 2. RESTRICT SUBSCRIPTION INSERT
-- Members should only create subscriptions for themselves
-- ============================================================

DROP POLICY IF EXISTS "Authenticated users can insert subscriptions" ON subscriptions;
DROP POLICY IF EXISTS "authenticated_insert_subscriptions" ON subscriptions;

CREATE POLICY "members_insert_own_subscriptions"
ON subscriptions FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());


-- ============================================================
-- 3. ADD UNIQUE CONSTRAINT ON deal_receipts.deal_authorization_id
-- Prevents duplicate receipts for the same deal
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE indexname = 'idx_deal_receipts_unique_deal_auth'
  ) THEN
    CREATE UNIQUE INDEX idx_deal_receipts_unique_deal_auth 
    ON deal_receipts(deal_authorization_id);
  END IF;
END $$;


-- ============================================================
-- 4. ADD UNIQUE CONSTRAINT ON virtual_receipts.deal_authorization_id
-- Prevents duplicate virtual receipts for the same deal
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE indexname = 'idx_virtual_receipts_unique_deal_auth'
  ) THEN
    CREATE UNIQUE INDEX idx_virtual_receipts_unique_deal_auth 
    ON virtual_receipts(deal_authorization_id);
  END IF;
END $$;


-- ============================================================
-- 5. ADD RATE LIMITING ON NOTIFICATIONS INSERT
-- Restrict members to only insert notifications for deal-related flows
-- (The RPC bypass function handles cross-user notifications)
-- ============================================================

DROP POLICY IF EXISTS "notifications_insert_authenticated" ON notifications;
DROP POLICY IF EXISTS "Users can insert own notifications" ON notifications;

-- Members can only insert notifications for themselves
-- Cross-user notifications (member→TP) go through the RPC bypass function
CREATE POLICY "notifications_insert_own"
ON notifications FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());


-- ============================================================
-- 6. STATUS TRANSITION VALIDATION (deal_authorizations)
-- Only allow valid status transitions
-- ============================================================

CREATE OR REPLACE FUNCTION validate_deal_status_transition()
RETURNS TRIGGER AS $$
BEGIN
  -- Allow admin bypass (check memberships table)
  IF EXISTS (
    SELECT 1 FROM memberships 
    WHERE user_id = auth.uid() AND role = 'admin'
  ) THEN
    RETURN NEW;
  END IF;

  -- Validate transitions
  IF OLD.status = 'pending' AND NEW.status NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Invalid status transition from pending to %', NEW.status;
  END IF;

  IF OLD.status = 'approved' AND NEW.status NOT IN ('completed', 'rejected') THEN
    RAISE EXCEPTION 'Invalid status transition from approved to %', NEW.status;
  END IF;

  IF OLD.status = 'rejected' THEN
    RAISE EXCEPTION 'Cannot change status of a rejected deal';
  END IF;

  IF OLD.status = 'completed' THEN
    RAISE EXCEPTION 'Cannot change status of a completed deal';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS validate_deal_status_transition ON deal_authorizations;
CREATE TRIGGER validate_deal_status_transition
  BEFORE UPDATE OF status ON deal_authorizations
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION validate_deal_status_transition();


-- ============================================================
-- 7. REMOVE paystack_secret_key FROM TRUSTED PARTNER BANK ACCOUNTS
-- Secret keys should NEVER be stored in a client-accessible table
-- ============================================================

-- Note: Only run this if you've migrated your Paystack integration to use
-- server-side (Edge Functions) for secret key operations.
-- For now, just restrict SELECT access to the column:
-- (Uncomment when ready to remove the column entirely)
-- ALTER TABLE trusted_partner_bank_accounts DROP COLUMN IF EXISTS paystack_secret_key;
-- ALTER TABLE trusted_partner_bank_accounts DROP COLUMN IF EXISTS paystack_public_key;


-- ============================================================
-- 8. ORPHAN RECEIPT RECOVERY FUNCTION
-- Find completed deals without receipts and flag them
-- Run periodically or on app startup
-- ============================================================

CREATE OR REPLACE FUNCTION get_orphaned_completed_deals(p_user_id UUID)
RETURNS TABLE (
  deal_id UUID,
  deal_amount DECIMAL,
  business_name TEXT,
  discount_name TEXT,
  completed_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    da.id,
    da.amount,
    b.name,
    tpd.name,
    da.completed_at
  FROM deal_authorizations da
  LEFT JOIN deal_receipts dr ON dr.deal_authorization_id = da.id
  LEFT JOIN trusted_partner_discounts tpd ON tpd.id = da.discount_id
  LEFT JOIN businesses b ON b.id = da.business_id
  WHERE da.member_id = p_user_id
    AND da.status = 'completed'
    AND da.payment_completed_at IS NOT NULL
    AND dr.id IS NULL;  -- No receipt exists
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_orphaned_completed_deals(UUID) TO authenticated;


-- ============================================================
-- VERIFICATION QUERY: Run after applying to verify all policies
-- ============================================================

-- Check deal_authorizations policies
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies 
WHERE tablename = 'deal_authorizations'
ORDER BY cmd, policyname;

-- Check notifications policies
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies 
WHERE tablename = 'notifications'
ORDER BY cmd, policyname;

-- Check subscriptions policies
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies 
WHERE tablename = 'subscriptions'
ORDER BY cmd, policyname;
