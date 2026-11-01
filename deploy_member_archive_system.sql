-- =====================================================
-- DEPLOYMENT SCRIPT: Member Deactivation for Re-signup Autofill
-- Run this script in Supabase SQL Editor to deploy all changes
-- =====================================================

-- STEP 1: Ensure deactivation columns exist in profiles table
-- =====================================================
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS is_deactivated BOOLEAN DEFAULT FALSE;

ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS deactivation_reason TEXT;

ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS deactivated_at TIMESTAMP WITH TIME ZONE;

-- Create index for fast deactivated profile lookup
CREATE INDEX IF NOT EXISTS idx_profiles_is_deactivated 
ON public.profiles(is_deactivated);

CREATE INDEX IF NOT EXISTS idx_profiles_email_deactivated 
ON public.profiles(LOWER(email), is_deactivated);

-- STEP 2: Update admin_delete_member_data function to deactivate instead of delete
-- =====================================================
CREATE OR REPLACE FUNCTION admin_delete_member_data(member_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSONB;
  member_email TEXT;
  member_name TEXT;
  col_name TEXT;
  sql TEXT;
BEGIN
  -- Verify the user is a member and get their details
  SELECT email, name 
  INTO member_email, member_name
  FROM profiles
  WHERE id = member_user_id AND role = 'member';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % is not a member or does not exist', member_user_id;
  END IF;

  result := jsonb_build_object(
    'member_id', member_user_id,
    'email', member_email,
    'name', member_name,
    'action', 'deactivated'
  );

  -- Mark profile as deactivated (keeps profile data for signup autofill)
  UPDATE profiles 
  SET 
    is_deactivated = true,
    deactivated_at = NOW(),
    deactivation_reason = 'Admin deletion',
    updated_at = NOW()
  WHERE id = member_user_id;
  
  result := result || jsonb_build_object('profile_deactivated', true);

  -- Deactivate all QR codes
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_qr_codes') THEN
    UPDATE user_qr_codes 
    SET is_active = false 
    WHERE user_id = member_user_id AND is_active = true;
    result := result || jsonb_build_object('qr_codes_deactivated', true);
  END IF;

  -- Update subscription status to deactivated
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='subscriptions') THEN
    UPDATE subscriptions 
    SET status = 'deactivated', updated_at = NOW()
    WHERE user_id = member_user_id AND status != 'deactivated';
    result := result || jsonb_build_object('subscription_deactivated', true);
  END IF;

  -- Delete member_receipts (cleanup)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='member_receipts' AND column_name='member_id') THEN
    EXECUTE 'DELETE FROM member_receipts WHERE member_id = $1' USING member_user_id;
    result := result || jsonb_build_object('member_receipts_deleted', true);
  END IF;

  -- Delete deal_authorizations (cleanup)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='deal_authorizations' AND column_name='member_id') THEN
    EXECUTE 'DELETE FROM deal_authorizations WHERE member_id = $1' USING member_user_id;
    result := result || jsonb_build_object('deal_authorizations_deleted', true);
  END IF;

  -- Delete payments (cleanup)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='payments') THEN
    DELETE FROM payments WHERE user_id = member_user_id;
    result := result || jsonb_build_object('payments_deleted', true);
  END IF;

  -- Delete notifications (cleanup)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='notifications') THEN
    DELETE FROM notifications WHERE user_id = member_user_id;
    result := result || jsonb_build_object('notifications_deleted', true);
  END IF;

  RETURN result::json;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to deactivate member: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_member_data(UUID) TO authenticated;

-- Keep old function for backward compatibility
CREATE OR REPLACE FUNCTION admin_delete_member(member_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE NOTICE 'admin_delete_member is deprecated. Use admin_delete_member_data';
  RETURN admin_delete_member_data(member_user_id);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_member(UUID) TO authenticated;

-- STEP 3: Verification queries
-- =====================================================
SELECT 'Deployment Complete! Running verification checks...' as status;

SELECT 
    'is_deactivated column' as check_name,
    CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'profiles' AND column_name = 'is_deactivated'
    ) 
        THEN '✅ Exists' 
        ELSE '❌ Missing' 
    END as status;

SELECT 
    'deactivation_reason column' as check_name,
    CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'profiles' AND column_name = 'deactivation_reason'
    ) 
        THEN '✅ Exists' 
        ELSE '❌ Missing' 
    END as status;

SELECT 
    'deactivated_at column' as check_name,
    CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'profiles' AND column_name = 'deactivated_at'
    ) 
        THEN '✅ Exists' 
        ELSE '❌ Missing' 
    END as status;

SELECT 
    'Deactivated profiles index' as check_name,
    CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_profiles_is_deactivated') 
        THEN '✅ Created' 
        ELSE '⚠️ Missing (non-critical)' 
    END as status;

SELECT 
    'admin_delete_member_data function' as check_name,
    CASE WHEN EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'admin_delete_member_data'
    ) 
        THEN '✅ Updated' 
        ELSE '❌ Missing' 
    END as status;

SELECT 'All checks complete! System ready for testing.' as final_status;
