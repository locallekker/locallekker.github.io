-- Create tp_inquiries table for storing trusted partner interest form submissions
-- These are potential TPs who have not yet been signed up by admin

CREATE TABLE IF NOT EXISTS tp_inquiries (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  surname TEXT NOT NULL,
  city TEXT,
  business_name TEXT NOT NULL,
  business_type TEXT,
  email TEXT NOT NULL,
  contact_number TEXT,
  sells_fresh_produce BOOLEAN NOT NULL DEFAULT false,
  sells_alcohol BOOLEAN NOT NULL DEFAULT false,
  offers_sports_activities BOOLEAN NOT NULL DEFAULT false,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'contacted', 'completed', 'declined')),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Keep existing installations aligned with the interest form payload.
ALTER TABLE tp_inquiries
  ADD COLUMN IF NOT EXISTS sells_fresh_produce BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sells_alcohol BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS offers_sports_activities BOOLEAN NOT NULL DEFAULT false;

-- RLS policies
ALTER TABLE tp_inquiries ENABLE ROW LEVEL SECURITY;

-- Allow anonymous inserts (form is submitted without auth)
CREATE POLICY "Anyone can submit a TP inquiry"
  ON tp_inquiries
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- Only admin can read inquiries
CREATE POLICY "Admin can read TP inquiries"
  ON tp_inquiries
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.memberships
      WHERE user_id = auth.uid() AND role = 'admin'
    )
  );

-- Only admin can update inquiries (change status, add notes)
CREATE POLICY "Admin can update TP inquiries"
  ON tp_inquiries
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.memberships
      WHERE user_id = auth.uid() AND role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.memberships
      WHERE user_id = auth.uid() AND role = 'admin'
    )
  );

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_tp_inquiries_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tp_inquiries_updated_at
  BEFORE UPDATE ON tp_inquiries
  FOR EACH ROW
  EXECUTE FUNCTION update_tp_inquiries_updated_at();
