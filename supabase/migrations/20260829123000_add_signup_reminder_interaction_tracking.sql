BEGIN;

ALTER TABLE public.member_signup_reminders
  ADD COLUMN IF NOT EXISTS tracking_token UUID NOT NULL DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS opened_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_opened_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS open_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS opted_out_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS idx_member_signup_reminders_tracking_token
  ON public.member_signup_reminders (tracking_token);

DROP FUNCTION IF EXISTS public.claim_pending_member_signup_reminders();
CREATE FUNCTION public.claim_pending_member_signup_reminders()
RETURNS TABLE (
  user_id UUID,
  email TEXT,
  member_name TEXT,
  tracking_token UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.member_signup_reminders (user_id)
  SELECT p.id
  FROM public.profiles p
  WHERE p.role = 'member'
    AND p.subscription = 'pending'
    AND p.created_at <= NOW() - INTERVAL '24 hours'
    AND NULLIF(BTRIM(COALESCE(p.email, '')), '') IS NOT NULL
  ON CONFLICT (user_id, reminder_type) DO NOTHING;

  RETURN QUERY
  UPDATE public.member_signup_reminders r
  SET
    attempt_count = r.attempt_count + 1,
    last_attempt_at = NOW(),
    updated_at = NOW()
  FROM public.profiles p
  WHERE r.user_id = p.id
    AND r.reminder_type = 'signup_completion_24h'
    AND r.email_sent_at IS NULL
    AND r.opted_out_at IS NULL
    AND p.role = 'member'
    AND p.subscription = 'pending'
    AND p.created_at <= NOW() - INTERVAL '24 hours'
    AND (r.last_attempt_at IS NULL OR r.last_attempt_at <= NOW() - INTERVAL '15 minutes')
  RETURNING
    p.id,
    p.email,
    COALESCE(NULLIF(BTRIM(CONCAT_WS(' ', p.name, p.surname)), ''), 'Member'),
    r.tracking_token;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_pending_member_signup_reminders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_pending_member_signup_reminders() TO service_role;

CREATE OR REPLACE FUNCTION public.record_member_signup_reminder_event(
  p_tracking_token UUID,
  p_event TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated INTEGER;
BEGIN
  IF p_event = 'open' THEN
    UPDATE public.member_signup_reminders
    SET
      opened_at = COALESCE(opened_at, NOW()),
      last_opened_at = NOW(),
      open_count = open_count + 1,
      updated_at = NOW()
    WHERE tracking_token = p_tracking_token;
  ELSIF p_event = 'opt_out' THEN
    UPDATE public.member_signup_reminders
    SET
      opted_out_at = COALESCE(opted_out_at, NOW()),
      updated_at = NOW()
    WHERE tracking_token = p_tracking_token;
  ELSE
    RETURN FALSE;
  END IF;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END;
$$;

REVOKE ALL ON FUNCTION public.record_member_signup_reminder_event(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_member_signup_reminder_event(UUID, TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.get_admin_member_signup_contact_statuses()
RETURNS TABLE (
  user_id UUID,
  reminder_sent_at TIMESTAMPTZ,
  opened_at TIMESTAMPTZ,
  last_opened_at TIMESTAMPTZ,
  open_count INTEGER,
  opted_out_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT
    r.user_id,
    r.email_sent_at,
    r.opened_at,
    r.last_opened_at,
    r.open_count,
    r.opted_out_at
  FROM public.member_signup_reminders r;
END;
$$;

REVOKE ALL ON FUNCTION public.get_admin_member_signup_contact_statuses() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_admin_member_signup_contact_statuses() TO authenticated;

COMMIT;