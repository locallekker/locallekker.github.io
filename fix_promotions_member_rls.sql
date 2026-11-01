-- Migration: Restrict member visibility of promotions to email-allowlisted members only
-- Previously members could read ALL active promotions.
-- Now a member can only SELECT a promotion if their auth email is in
-- promotion_participant_emails for that promotion.
-- Admin access remains unrestricted.

-- Step 1: Drop the old blanket read policy for members
DROP POLICY IF EXISTS "Members can view active promotions" ON promotions;

-- Step 2: Add the new email-gated read policy
-- A member can see a promotion only when their email appears in
-- promotion_participant_emails for that promotion.
CREATE POLICY "Members can view their eligible promotions"
  ON promotions
  FOR SELECT
  TO authenticated
  USING (
    -- Admins bypass the filter entirely
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role = 'admin'
    )
    OR
    -- Regular members: only see promotions they are listed for
    EXISTS (
      SELECT 1 FROM promotion_participant_emails ppe
      WHERE ppe.promotion_id = promotions.id
        AND ppe.email = lower(trim(auth.email()))
    )
  );
