-- ============================================================
-- Allow members to claim their own promotion participant email slot.
-- Called by the app after a member signs up for a promotion,
-- so the admin sees the email move from PENDING → CLAIMED.
-- ============================================================

DROP POLICY IF EXISTS "members_update_own_participant_claim" ON public.promotion_participant_emails;
CREATE POLICY "members_update_own_participant_claim"
  ON public.promotion_participant_emails
  FOR UPDATE
  USING (
    auth.role() = 'authenticated'
    AND lower(email) = lower(
      coalesce((SELECT p.email FROM public.profiles p WHERE p.id = auth.uid()), '')
    )
  )
  WITH CHECK (
    claimed_by = auth.uid()
    AND is_claimed = true
  );
