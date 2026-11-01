-- Adds columns to track Member Terms acceptance.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS member_terms_accepted BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS member_terms_accepted_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS member_terms_version TEXT NULL;

COMMENT ON COLUMN profiles.member_terms_accepted IS 'True when member accepted the Member Terms & Conditions.';
COMMENT ON COLUMN profiles.member_terms_accepted_at IS 'Timestamp when member terms acceptance was recorded.';
COMMENT ON COLUMN profiles.member_terms_version IS 'Version string of the terms accepted by member.';

-- Helpful partial index: find members who haven\'t accepted yet
CREATE INDEX IF NOT EXISTS idx_profiles_member_terms_unaccepted ON profiles(id) WHERE member_terms_accepted = FALSE AND role = 'member';
