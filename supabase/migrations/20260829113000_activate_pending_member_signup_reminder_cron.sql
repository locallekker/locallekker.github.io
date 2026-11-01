BEGIN;

DO $$
DECLARE
  v_cron_secret TEXT;
  v_command TEXT;
  v_existing_job_id BIGINT;
BEGIN
  SELECT (REGEXP_MATCH(
    command,
    $pattern$'x-cron-secret'\s*,\s*'([^']+)'$pattern$
  ))[1]
  INTO v_cron_secret
  FROM cron.job
  WHERE command ~ $pattern$'x-cron-secret'\s*,\s*'([^']+)'$pattern$
  ORDER BY jobid
  LIMIT 1;

  IF NULLIF(v_cron_secret, '') IS NULL THEN
    RAISE EXCEPTION 'No existing x-cron-secret was found in cron.job';
  END IF;

  SELECT jobid
  INTO v_existing_job_id
  FROM cron.job
  WHERE jobname = 'hourly-pending-member-signup-reminder'
  LIMIT 1;

  IF v_existing_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_existing_job_id);
  END IF;

  v_command := FORMAT(
    $command$
      SELECT net.http_post(
        url := 'https://qdrotavcmmevhgveodcp.supabase.co/functions/v1/pending-member-signup-reminder',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', %L
        ),
        body := '{}'::jsonb
      );
    $command$,
    v_cron_secret
  );

  PERFORM cron.schedule(
    'hourly-pending-member-signup-reminder',
    '0 * * * *',
    v_command
  );
END;
$$;

COMMIT;