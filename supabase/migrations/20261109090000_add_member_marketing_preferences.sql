BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS marketing_email_consent BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS marketing_whatsapp_consent BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS marketing_preferences_recorded_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS marketing_preferences_wording TEXT,
  ADD COLUMN IF NOT EXISTS marketing_preferences_version TEXT;

COMMENT ON COLUMN public.profiles.marketing_email_consent IS
  'Whether the member opted in to marketing by email.';
COMMENT ON COLUMN public.profiles.marketing_whatsapp_consent IS
  'Whether the member opted in to marketing by WhatsApp.';
COMMENT ON COLUMN public.profiles.marketing_preferences_recorded_at IS
  'Server timestamp when the member selected or updated marketing preferences.';
COMMENT ON COLUMN public.profiles.marketing_preferences_wording IS
  'Exact marketing preference wording shown when the member made the selection.';
COMMENT ON COLUMN public.profiles.marketing_preferences_version IS
  'Version of the marketing preference wording shown to the member.';

CREATE OR REPLACE FUNCTION public.save_member_marketing_preferences(
  p_email_consent BOOLEAN,
  p_whatsapp_consent BOOLEAN,
  p_consent_wording TEXT,
  p_consent_version TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_consent_wording IS NULL OR btrim(p_consent_wording) = '' THEN
    RAISE EXCEPTION 'Marketing preference wording is required';
  END IF;

  IF p_consent_version IS NULL OR btrim(p_consent_version) = '' THEN
    RAISE EXCEPTION 'Marketing preference version is required';
  END IF;

  UPDATE public.profiles
  SET marketing_email_consent = COALESCE(p_email_consent, FALSE),
      marketing_whatsapp_consent = COALESCE(p_whatsapp_consent, FALSE),
      marketing_preferences_recorded_at = NOW(),
      marketing_preferences_wording = p_consent_wording,
      marketing_preferences_version = p_consent_version,
      updated_at = NOW()
  WHERE id = v_user_id;

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.save_member_marketing_preferences(BOOLEAN, BOOLEAN, TEXT, TEXT)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_member_marketing_preferences(BOOLEAN, BOOLEAN, TEXT, TEXT)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.member_terms_current_status(
  p_user_id UUID,
  p_version TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_current BOOLEAN;
BEGIN
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot read terms status for another user';
  END IF;

  SELECT COALESCE(member_terms_accepted, FALSE)
         AND member_terms_version = p_version
    INTO v_is_current
  FROM public.profiles
  WHERE id = p_user_id;

  RETURN COALESCE(v_is_current, FALSE);
END;
$$;

REVOKE ALL ON FUNCTION public.member_terms_current_status(UUID, TEXT)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.member_terms_current_status(UUID, TEXT)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.claim_pending_member_signup_reminders()
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
    AND p.marketing_email_consent = TRUE
    AND p.created_at <= NOW() - INTERVAL '24 hours'
    AND NULLIF(BTRIM(COALESCE(p.email, '')), '') IS NOT NULL
  ON CONFLICT (user_id, reminder_type) DO NOTHING;

  RETURN QUERY
  UPDATE public.member_signup_reminders r
  SET attempt_count = r.attempt_count + 1,
      last_attempt_at = NOW(),
      updated_at = NOW()
  FROM public.profiles p
  WHERE r.user_id = p.id
    AND r.reminder_type = 'signup_completion_24h'
    AND r.email_sent_at IS NULL
    AND r.opted_out_at IS NULL
    AND p.role = 'member'
    AND p.subscription = 'pending'
    AND p.marketing_email_consent = TRUE
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
    SET opened_at = COALESCE(opened_at, NOW()),
        last_opened_at = NOW(),
        open_count = open_count + 1,
        updated_at = NOW()
    WHERE tracking_token = p_tracking_token;
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RETURN v_updated = 1;
  ELSIF p_event = 'opt_out' THEN
    UPDATE public.member_signup_reminders
    SET opted_out_at = COALESCE(opted_out_at, NOW()),
        updated_at = NOW()
    WHERE tracking_token = p_tracking_token;

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    IF v_updated = 1 THEN
      UPDATE public.profiles p
      SET marketing_email_consent = FALSE,
          marketing_preferences_recorded_at = NOW(),
          marketing_preferences_wording =
            'User withdrew email marketing consent via the signup reminder opt-out link.',
          updated_at = NOW()
      FROM public.member_signup_reminders r
      WHERE r.tracking_token = p_tracking_token
        AND p.id = r.user_id;
    END IF;
    RETURN v_updated = 1;
  ELSE
    RETURN FALSE;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.record_member_signup_reminder_event(UUID, TEXT)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_member_signup_reminder_event(UUID, TEXT)
  TO service_role;

COMMIT;