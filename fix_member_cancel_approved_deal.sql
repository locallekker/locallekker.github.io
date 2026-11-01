-- ============================================================
-- FIX: Allow members to cancel approved deals
-- Members should be able to cancel deals even after TP approval
-- (before payment is completed)
-- ============================================================

-- Update the member deal update trigger to allow approved → rejected
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

    -- Members can cancel their pending deals (set to rejected)
    IF OLD.status = 'pending' AND NEW.status = 'rejected' THEN
      RETURN NEW;
    END IF;

    -- Members can cancel approved deals before payment (set to rejected)
    IF OLD.status = 'approved' AND NEW.status = 'rejected' THEN
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
