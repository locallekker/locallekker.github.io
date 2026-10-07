-- Fix: members renewed (auto or manual) but their QR stayed expired.
--
-- Root cause: UNIQUE (user_id, is_active) allowed only ONE inactive QR row per
-- member. From a member's second renewal onward, "deactivate old QR" failed
-- (an inactive row already existed) and "insert new active QR" then failed
-- (the old row was still active). Both errors were swallowed by the client, so
-- the subscription was extended while the QR kept its old expires_at.
--
-- Fix:
--   1. Replace the constraint with a partial unique index (one ACTIVE QR per user,
--      unlimited inactive history rows).
--   2. Keep the active QR's expires_at in sync with the member's latest active
--      subscription via a trigger, regardless of which code path renews it
--      (app, paystack-webhook, scheduled-renewal-worker, admin).
--   3. Backfill members whose QR is already out of sync.

BEGIN;

-- 1. Constraint ------------------------------------------------------------

-- Collapse any duplicate active rows (keep most recent) before the new index.
WITH ranked AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY user_id
           ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST
         ) AS rn
  FROM public.user_qr_codes
  WHERE is_active = true
)
UPDATE public.user_qr_codes q
SET is_active = false
FROM ranked r
WHERE q.id = r.id AND r.rn > 1;

ALTER TABLE public.user_qr_codes
  DROP CONSTRAINT IF EXISTS user_qr_codes_user_id_is_active_key;

CREATE UNIQUE INDEX IF NOT EXISTS user_qr_codes_one_active_per_user
  ON public.user_qr_codes (user_id)
  WHERE is_active = true;

-- 2. Sync helper + trigger -------------------------------------------------

CREATE OR REPLACE FUNCTION public.ensure_member_qr_matches_subscription(
  p_user_id uuid,
  p_period_end timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_qr_id uuid;
  v_name text;
  v_surname text;
BEGIN
  IF p_user_id IS NULL OR p_period_end IS NULL OR p_period_end <= now() THEN
    RETURN;
  END IF;

  SELECT id INTO v_qr_id
  FROM public.user_qr_codes
  WHERE user_id = p_user_id AND is_active = true
  LIMIT 1;

  IF v_qr_id IS NOT NULL THEN
    UPDATE public.user_qr_codes
    SET expires_at = p_period_end
    WHERE id = v_qr_id
      AND expires_at IS DISTINCT FROM p_period_end;
    RETURN;
  END IF;

  SELECT COALESCE(NULLIF(name, ''), 'Unknown'), COALESCE(NULLIF(surname, ''), 'Unknown')
  INTO v_name, v_surname
  FROM public.profiles
  WHERE id = p_user_id;

  -- The member app rotates qr_code to a short-lived user_qr_v2 payload on open;
  -- this legacy payload is valid for validate_member_qr_scan until then.
  INSERT INTO public.user_qr_codes (user_id, qr_code, name, surname, is_active, expires_at)
  VALUES (
    p_user_id,
    jsonb_build_object(
      'user_id', p_user_id,
      'name', COALESCE(v_name, 'Unknown'),
      'surname', COALESCE(v_surname, 'Unknown'),
      'timestamp', (extract(epoch FROM clock_timestamp()) * 1000)::bigint,
      'random', floor(random() * 999999)::int,
      'type', 'user_qr'
    )::text,
    COALESCE(v_name, 'Unknown'),
    COALESCE(v_surname, 'Unknown'),
    true,
    p_period_end
  )
  ON CONFLICT (user_id) WHERE is_active = true
  DO UPDATE SET expires_at = EXCLUDED.expires_at;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_member_qr_matches_subscription(uuid, timestamptz) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.sync_member_qr_on_subscription_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status <> 'active' OR NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Only the member's latest subscription row drives QR expiry.
  IF EXISTS (
    SELECT 1 FROM public.subscriptions s
    WHERE s.user_id = NEW.user_id
      AND s.id <> NEW.id
      AND s.created_at > NEW.created_at
  ) THEN
    RETURN NEW;
  END IF;

  PERFORM public.ensure_member_qr_matches_subscription(NEW.user_id, NEW.current_period_end);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_member_qr_on_subscription_change ON public.subscriptions;
CREATE TRIGGER sync_member_qr_on_subscription_change
  AFTER INSERT OR UPDATE OF status, current_period_end ON public.subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_member_qr_on_subscription_change();

-- 3. Backfill --------------------------------------------------------------

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT DISTINCT ON (user_id) user_id, status, current_period_end
    FROM public.subscriptions
    ORDER BY user_id, created_at DESC
  LOOP
    IF r.status = 'active' THEN
      PERFORM public.ensure_member_qr_matches_subscription(r.user_id, r.current_period_end);
    END IF;
  END LOOP;
END;
$$;

COMMIT;
