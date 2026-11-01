BEGIN;

-- A read-only, allowlisted projection, not anonymous access to business or
-- owner profile rows. Optional catalogue fields support older schemas.
CREATE OR REPLACE VIEW public.guest_business_catalogue
WITH (security_barrier = true) AS
SELECT
  b.id,
  b.owner_member_id,
  b.name,
  b.category,
  b.address,
  to_jsonb(b) ->> 'city' AS city,
  to_jsonb(b) ->> 'logo_url' AS logo_url,
  to_jsonb(b) ->> 'facebook_handle' AS facebook_handle,
  to_jsonb(b) ->> 'instagram_handle' AS instagram_handle,
  to_jsonb(b) ->> 'website_url' AS website_url,
  to_jsonb(b) ->> 'business_email' AS business_email,
  b.contact_number,
  b.contact_email,
  to_jsonb(b) ->> 'produce_description' AS produce_description,
  to_jsonb(b) ->> 'alcohol_description' AS alcohol_description,
  to_jsonb(b) ->> 'sports_description' AS sports_description,
  coalesce((to_jsonb(b) ->> 'sells_fresh_produce')::boolean, false) AS sells_fresh_produce,
  coalesce((to_jsonb(b) ->> 'sells_alcohol')::boolean, false) AS sells_alcohol,
  coalesce((to_jsonb(b) ->> 'offers_sports_activities')::boolean, false) AS offers_sports_activities,
  coalesce((to_jsonb(b) ->> 'liquor_license_verified')::boolean, false) AS liquor_license_verified
FROM public.businesses b
WHERE EXISTS (
  SELECT 1 FROM public.trusted_partner_discounts d
  WHERE d.is_active = true
    AND (d.trusted_partner_id = b.owner_member_id OR d.business_id = b.id)
);

REVOKE ALL ON public.guest_business_catalogue FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.guest_business_catalogue TO anon, authenticated;

-- Keep the supporting-app restriction and all authenticated policies intact.
GRANT SELECT ON public.trusted_partner_discounts TO anon;
DROP POLICY IF EXISTS "Guests can browse active discounts" ON public.trusted_partner_discounts;
CREATE POLICY "Guests can browse active discounts"
  ON public.trusted_partner_discounts FOR SELECT TO anon
  USING (is_active = true);
DROP POLICY IF EXISTS "Guests cannot browse inactive discounts" ON public.trusted_partner_discounts;
CREATE POLICY "Guests cannot browse inactive discounts"
  ON public.trusted_partner_discounts AS RESTRICTIVE FOR SELECT TO anon
  USING (is_active = true);

-- This RPC reveals only payment availability, never payout/banking details.
GRANT EXECUTE ON FUNCTION public.discount_accepts_in_app_payment(uuid) TO anon;

COMMIT;
