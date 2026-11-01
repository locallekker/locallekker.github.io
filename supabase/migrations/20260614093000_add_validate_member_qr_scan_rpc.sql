-- Validate scanned member QR codes against the active server record.
-- Supports legacy user_qr payloads and short-lived user_qr_v2 payloads.

BEGIN;

CREATE OR REPLACE FUNCTION public.validate_member_qr_scan(scanned_qr text)
RETURNS TABLE(
  valid boolean,
  member_id uuid,
  name text,
  surname text,
  reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  payload jsonb;
  payload_user_id uuid;
  payload_type text;
  payload_exp bigint;
  qr_row public.user_qr_codes%ROWTYPE;
BEGIN
  IF scanned_qr IS NULL OR btrim(scanned_qr) = '' THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, 'Empty QR payload.';
    RETURN;
  END IF;

  BEGIN
    payload := scanned_qr::jsonb;
  EXCEPTION WHEN others THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, 'Invalid QR format.';
    RETURN;
  END;

  payload_type := payload ->> 'type';
  IF payload_type IS DISTINCT FROM 'user_qr' AND payload_type IS DISTINCT FROM 'user_qr_v2' THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, 'Not a member QR code.';
    RETURN;
  END IF;

  BEGIN
    payload_user_id := (payload ->> 'user_id')::uuid;
  EXCEPTION WHEN others THEN
    payload_user_id := NULL;
  END;

  IF payload_user_id IS NULL THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, 'Missing member ID in QR code.';
    RETURN;
  END IF;

  IF payload_type = 'user_qr_v2' THEN
    BEGIN
      payload_exp := (payload ->> 'exp')::bigint;
    EXCEPTION WHEN others THEN
      payload_exp := NULL;
    END;

    IF payload_exp IS NULL THEN
      RETURN QUERY SELECT false, NULL::uuid, NULL::text, NULL::text, 'Invalid QR expiry.';
      RETURN;
    END IF;

    IF now() > to_timestamp(payload_exp) THEN
      RETURN QUERY SELECT false, payload_user_id, NULL::text, NULL::text, 'QR code expired. Ask member to refresh.';
      RETURN;
    END IF;
  END IF;

  SELECT *
  INTO qr_row
  FROM public.user_qr_codes u
  WHERE u.user_id = payload_user_id
    AND u.qr_code = scanned_qr
    AND u.is_active = true
  ORDER BY u.updated_at DESC NULLS LAST, u.created_at DESC
  LIMIT 1;

  IF qr_row.id IS NULL THEN
    RETURN QUERY SELECT false, payload_user_id, NULL::text, NULL::text, 'QR not recognized. Ask member to open a fresh QR.';
    RETURN;
  END IF;

  IF qr_row.expires_at <= now() THEN
    RETURN QUERY SELECT false, payload_user_id, NULL::text, NULL::text, 'Member QR inactive or subscription expired.';
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    true,
    qr_row.user_id,
    COALESCE(NULLIF(qr_row.name, ''), payload ->> 'name', 'Unknown')::text,
    COALESCE(NULLIF(qr_row.surname, ''), payload ->> 'surname', 'Unknown')::text,
    NULL::text;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_member_qr_scan(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_member_qr_scan(text) TO authenticated;

COMMIT;
