-- Adds columns to track Trusted Partner Terms acceptance.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS partner_terms_accepted BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS partner_terms_accepted_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS partner_terms_version TEXT NULL;

COMMENT ON COLUMN profiles.partner_terms_accepted IS 'True when trusted partner accepted the Trusted Partner Agreement.';
COMMENT ON COLUMN profiles.partner_terms_accepted_at IS 'Timestamp when terms acceptance was recorded.';
COMMENT ON COLUMN profiles.partner_terms_version IS 'Version string of the terms accepted by trusted partner.';

-- Helpful partial index for querying partners needing acceptance follow-up.
CREATE INDEX IF NOT EXISTS idx_profiles_partner_terms_unaccepted ON profiles(id) WHERE partner_terms_accepted = FALSE AND role = 'trusted_partner';
