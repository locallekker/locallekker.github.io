-- Prevent the app and scheduled worker from charging the same billing period.

ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS renewal_in_progress_at TIMESTAMP WITH TIME ZONE;

CREATE OR REPLACE FUNCTION public.claim_subscription_renewal(
  p_subscription_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.subscriptions s
  SET renewal_in_progress_at = clock_timestamp(),
      updated_at = clock_timestamp()
  WHERE s.id = p_subscription_id
    AND (s.user_id = auth.uid() OR auth.role() = 'service_role')
    AND s.status = 'active'
    AND s.auto_renew = true
    AND s.current_period_end <= clock_timestamp() + INTERVAL '1 hour'
    AND (
      s.renewal_in_progress_at IS NULL
      OR s.renewal_in_progress_at < clock_timestamp() - INTERVAL '24 hours'
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.subscription_renewals sr
      WHERE sr.subscription_id = s.id
        AND sr.status = 'success'
        AND sr.renewal_date >= s.current_period_end - INTERVAL '1 hour'
        AND sr.renewal_date <= s.current_period_end + INTERVAL '25 hours'
    );

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_subscription_renewal_claim(
  p_subscription_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.subscriptions
  SET renewal_in_progress_at = NULL,
      updated_at = clock_timestamp()
  WHERE id = p_subscription_id
    AND (user_id = auth.uid() OR auth.role() = 'service_role');
END;
$$;

REVOKE ALL ON FUNCTION public.claim_subscription_renewal(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_subscription_renewal(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.release_subscription_renewal_claim(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.release_subscription_renewal_claim(UUID) TO authenticated, service_role;