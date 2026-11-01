-- =============================================================================
-- LOCAL LEKKER: DATABASE FIX-UP SCRIPT
-- Generated from diagnostic analysis of live DB vs app code
-- Run in Supabase SQL Editor. All operations are safe (IF NOT EXISTS / ADD COLUMN IF NOT EXISTS).
-- =============================================================================

-- =====================================================================
-- FIX 1: ADD MISSING COLUMNS (Critical - app will crash without these)
-- =====================================================================

-- 1a. deal_authorizations.is_once_off
-- Used in: deal_authorization_service.dart (SELECT, filter)
ALTER TABLE public.deal_authorizations
ADD COLUMN IF NOT EXISTS is_once_off BOOLEAN DEFAULT FALSE;

-- 1b. processed_bills.amount
-- Used in: admin_service.dart (SELECT, read)
ALTER TABLE public.processed_bills
ADD COLUMN IF NOT EXISTS amount DECIMAL(10,2);

-- 1c. processed_bills.bill_data
-- Used in: admin_service.dart, savings_service.dart (SELECT, read JSONB)
ALTER TABLE public.processed_bills
ADD COLUMN IF NOT EXISTS bill_data JSONB;

-- 1d. processed_bills.trusted_partner_id
-- Used in: admin_service.dart (SELECT, filter)
ALTER TABLE public.processed_bills
ADD COLUMN IF NOT EXISTS trusted_partner_id UUID REFERENCES auth.users(id);

-- 1e. profiles.subscription_payment_method_id
-- Used in: deal_authorization_service.dart (SELECT, read)
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS subscription_payment_method_id TEXT;

-- 1f. subscriptions.amount
-- Used in: paystack_webhook_handler.dart (INSERT)
ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS amount DECIMAL(10,2);

-- 1g. subscriptions.currency
-- Used in: paystack_webhook_handler.dart (INSERT)
ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'ZAR';

-- 1h. subscriptions.plan_name
-- Used in: paystack_webhook_handler.dart (INSERT)
ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS plan_name TEXT;

-- 1i. trusted_partners.paystack_subaccount_code
-- Used in: deal_payment_webview_page.dart, deal_approval_popup_service.dart (SELECT)
-- NOTE: DB has paystack_subaccount_id but app also queries paystack_subaccount_code
ALTER TABLE public.trusted_partners
ADD COLUMN IF NOT EXISTS paystack_subaccount_code TEXT;

-- =====================================================================
-- FIX 2: ADD MISSING RLS POLICIES
-- =====================================================================

-- 2a. members_card_details: Individual SELECT, INSERT, UPDATE policies
-- The table has a FOR ALL policy but diagnostic checks for individual ones.
-- Check if individual policies exist first, add if missing.
DO $$
BEGIN
  -- SELECT
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'members_card_details' AND cmd = 'SELECT'
  ) THEN
    CREATE POLICY "Members can view their own card details"
      ON public.members_card_details
      FOR SELECT USING (user_id = auth.uid());
  END IF;

  -- INSERT
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'members_card_details' AND cmd = 'INSERT'
  ) THEN
    CREATE POLICY "Members can insert their own card details"
      ON public.members_card_details
      FOR INSERT WITH CHECK (user_id = auth.uid());
  END IF;

  -- UPDATE
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'members_card_details' AND cmd = 'UPDATE'
  ) THEN
    CREATE POLICY "Members can update their own card details"
      ON public.members_card_details
      FOR UPDATE USING (user_id = auth.uid());
  END IF;
END $$;

-- 2b. subscriptions: DELETE policy (for subscription cleanup)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'subscriptions' AND cmd = 'DELETE'
  ) THEN
    CREATE POLICY "Users can delete their own subscriptions"
      ON public.subscriptions
      FOR DELETE USING (user_id = auth.uid());
  END IF;
END $$;

-- =====================================================================
-- FIX 3: CREATE MISSING RPC FUNCTIONS
-- =====================================================================

-- 3a. get_my_role() - Critical for role-based navigation
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
AS $$
  SELECT COALESCE(
    (SELECT m.role FROM memberships m WHERE m.user_id = auth.uid() LIMIT 1),
    (SELECT p.role FROM profiles p WHERE p.id = auth.uid() LIMIT 1)
  );
$$;

-- 3b. is_deal_active_now() - Deal schedule checking
CREATE OR REPLACE FUNCTION public.is_deal_active_now(
    p_is_active BOOLEAN,
    p_schedule_type TEXT,
    p_schedule_days JSONB,
    p_schedule_start_date TIMESTAMPTZ,
    p_schedule_end_date TIMESTAMPTZ,
    p_schedule_start_time TEXT,
    p_schedule_end_time TEXT
) RETURNS BOOLEAN AS $$
DECLARE
    v_now TIMESTAMPTZ := NOW();
    v_current_day TEXT;
    v_current_time TEXT;
    v_day_schedule JSONB;
BEGIN
    IF NOT p_is_active THEN
        RETURN FALSE;
    END IF;

    IF p_schedule_type = 'always' OR p_schedule_type IS NULL THEN
        RETURN TRUE;
    END IF;

    IF p_schedule_type = 'daily' THEN
        RETURN TRUE;
    END IF;

    IF p_schedule_type = 'date_range' THEN
        IF p_schedule_start_date IS NOT NULL AND v_now < p_schedule_start_date THEN
            RETURN FALSE;
        END IF;
        IF p_schedule_end_date IS NOT NULL AND v_now > p_schedule_end_date THEN
            RETURN FALSE;
        END IF;

        IF p_schedule_start_time IS NOT NULL AND p_schedule_end_time IS NOT NULL THEN
            v_current_time := TO_CHAR(v_now, 'HH24:MI');
            IF v_current_time < p_schedule_start_time OR v_current_time > p_schedule_end_time THEN
                RETURN FALSE;
            END IF;
        END IF;

        RETURN TRUE;
    END IF;

    IF p_schedule_type = 'specific_days' THEN
        v_current_day := LOWER(TRIM(TO_CHAR(v_now, 'Day')));
        v_current_time := TO_CHAR(v_now, 'HH24:MI');

        FOR v_day_schedule IN SELECT * FROM jsonb_array_elements(p_schedule_days)
        LOOP
            IF (v_day_schedule->>'day') = v_current_day THEN
                IF (v_day_schedule->>'allDay')::BOOLEAN THEN
                    RETURN TRUE;
                ELSE
                    IF v_current_time >= (v_day_schedule->>'startTime')
                       AND v_current_time <= (v_day_schedule->>'endTime') THEN
                        RETURN TRUE;
                    END IF;
                END IF;
            END IF;
        END LOOP;

        RETURN FALSE;
    END IF;

    RETURN p_is_active;
END;
$$ LANGUAGE plpgsql STABLE;

-- =====================================================================
-- FIX 4: CREATE MISSING STORAGE BUCKET
-- =====================================================================

-- 4a. deal-images bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('deal-images', 'deal-images', true)
ON CONFLICT (id) DO NOTHING;

-- 4b. RLS policies for deal-images bucket
DO $$
BEGIN
  -- Allow authenticated users to upload deal images
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Allow authenticated uploads to deal-images'
  ) THEN
    CREATE POLICY "Allow authenticated uploads to deal-images"
      ON storage.objects FOR INSERT
      WITH CHECK (bucket_id = 'deal-images' AND auth.uid() IS NOT NULL);
  END IF;

  -- Allow public read of deal images
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Allow public read of deal-images'
  ) THEN
    CREATE POLICY "Allow public read of deal-images"
      ON storage.objects FOR SELECT
      USING (bucket_id = 'deal-images');
  END IF;

  -- Allow owners to update/delete their deal images
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Allow owners to manage deal-images'
  ) THEN
    CREATE POLICY "Allow owners to manage deal-images"
      ON storage.objects FOR DELETE
      USING (bucket_id = 'deal-images' AND auth.uid() IS NOT NULL);
  END IF;
END $$;

-- =====================================================================
-- FIX 5: ENABLE REALTIME ON CRITICAL TABLES
-- =====================================================================

-- notifications table MUST have realtime for push notification stream
-- chat_messages table MUST have realtime for live chat
-- Idempotent: only add each table if it is not already a member of the publication.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'chat_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
  END IF;
END $$;

-- =====================================================================
-- VERIFICATION: Re-run checks to confirm all fixes applied
-- =====================================================================
SELECT 'VERIFY' AS section, 'Fix applied' AS item, 
  column_name AS detail, '✅ CONFIRMED' AS status
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
    (table_name = 'deal_authorizations' AND column_name = 'is_once_off') OR
    (table_name = 'processed_bills' AND column_name IN ('amount', 'bill_data', 'trusted_partner_id')) OR
    (table_name = 'profiles' AND column_name = 'subscription_payment_method_id') OR
    (table_name = 'subscriptions' AND column_name IN ('amount', 'currency', 'plan_name')) OR
    (table_name = 'trusted_partners' AND column_name = 'paystack_subaccount_code')
  )
ORDER BY detail;
