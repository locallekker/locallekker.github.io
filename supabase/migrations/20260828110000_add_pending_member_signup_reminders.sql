BEGIN;

CREATE TABLE IF NOT EXISTS public.member_signup_reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reminder_type TEXT NOT NULL DEFAULT 'signup_completion_24h',
  attempt_count INTEGER NOT NULL DEFAULT 0,
  last_attempt_at TIMESTAMPTZ,
  email_sent_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, reminder_type)
);

CREATE INDEX IF NOT EXISTS idx_member_signup_reminders_pending
  ON public.member_signup_reminders (reminder_type, last_attempt_at)
  WHERE email_sent_at IS NULL;

ALTER TABLE public.member_signup_reminders ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.claim_pending_member_signup_reminders()
RETURNS TABLE (
  user_id UUID,
  email TEXT,
  member_name TEXT
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
    AND p.role = 'member'
    AND p.subscription = 'pending'
    AND p.created_at <= NOW() - INTERVAL '24 hours'
    AND (r.last_attempt_at IS NULL OR r.last_attempt_at <= NOW() - INTERVAL '15 minutes')
  RETURNING
    p.id,
    p.email,
    COALESCE(NULLIF(BTRIM(CONCAT_WS(' ', p.name, p.surname)), ''), 'Member');
END;
$$;

REVOKE ALL ON FUNCTION public.claim_pending_member_signup_reminders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_pending_member_signup_reminders() TO service_role;

COMMIT;

-- Run this separately after enabling pg_cron and pg_net. Replace both placeholders.
/*
SELECT cron.schedule(
  'hourly-pending-member-signup-reminder',
  '0 * * * *',
  $$
    SELECT net.http_post(
      url := 'https://<PROJECT_REF>.supabase.co/functions/v1/pending-member-signup-reminder',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', '<CRON_SECRET>'
      ),
      body := '{}'::jsonb
    );
  $$
);
*/