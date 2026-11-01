-- Migration to fix trusted partner deletion function
-- Update the function to provide better error messages

CREATE OR REPLACE FUNCTION admin_delete_trusted_partner_data(tp_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count JSONB;
  tp_email TEXT;
  tp_name TEXT;
  business_ids UUID[] := ARRAY[]::UUID[];
  deal_ids UUID[] := ARRAY[]::UUID[];
  col_name TEXT;
  sql TEXT;
  deal_auth_ids UUID[] := ARRAY[]::UUID[];
BEGIN
  -- Verify the user is a trusted partner (check both profile role and trusted_partners table)
  SELECT p.email, p.name INTO tp_email, tp_name
  FROM profiles p
  WHERE p.id = tp_user_id AND p.role = 'trusted_partner';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % does not exist in profiles with trusted_partner role', tp_user_id;
  END IF;

  -- Also verify they have a trusted_partners record
  IF NOT EXISTS (SELECT 1 FROM trusted_partners WHERE user_id = tp_user_id) THEN
    RAISE EXCEPTION 'User % is not a trusted partner (no record in trusted_partners table)', tp_user_id;
  END IF;

  -- Helper: find appropriate owner column for businesses
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'businesses' AND column_name = 'user_id') THEN
    col_name := 'user_id';
  ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'businesses' AND column_name = 'owner_member_id') THEN
    col_name := 'owner_member_id';
  ELSE
    col_name := NULL;
  END IF;

  IF col_name IS NOT NULL THEN
    sql := format('SELECT array_agg(id) FROM public.businesses WHERE %I = $1', col_name);
    EXECUTE sql INTO business_ids USING tp_user_id;
  ELSE
    business_ids := ARRAY[]::UUID[];
  END IF;

  -- Get deals for those businesses
  IF business_ids IS NOT NULL AND array_length(business_ids,1) IS NOT NULL THEN
    SELECT array_agg(id) INTO deal_ids FROM trusted_partner_discounts WHERE business_id = ANY(business_ids);
  END IF;

  -- Get deal authorization IDs for those deals
  IF deal_ids IS NOT NULL AND array_length(deal_ids,1) IS NOT NULL THEN
    SELECT array_agg(id) INTO deal_auth_ids FROM deal_authorizations WHERE discount_id = ANY(deal_ids);
  END IF;

  deleted_count := jsonb_build_object(
    'tp_user_id', tp_user_id,
    'email', tp_email,
    'name', tp_name,
    'business_ids', COALESCE(business_ids, ARRAY[]::UUID[]),
    'deal_ids', COALESCE(deal_ids, ARRAY[]::UUID[]),
    'deal_auth_ids', COALESCE(deal_auth_ids, ARRAY[]::UUID[])
  );

  -- Delete deal-related data if present
  IF deal_auth_ids IS NOT NULL AND array_length(deal_auth_ids,1) IS NOT NULL THEN
    EXECUTE 'DELETE FROM deal_receipts WHERE deal_authorization_id = ANY($1)' USING deal_auth_ids;
    deleted_count := deleted_count || jsonb_build_object('deal_receipts_deleted', true);

    EXECUTE 'DELETE FROM virtual_receipts WHERE deal_authorization_id = ANY($1)' USING deal_auth_ids;
    deleted_count := deleted_count || jsonb_build_object('virtual_receipts_deleted', true);

    EXECUTE 'DELETE FROM deal_authorizations WHERE id = ANY($1)' USING deal_auth_ids;
    deleted_count := deleted_count || jsonb_build_object('deal_authorizations_deleted', true);
  END IF;

  -- Delete deal images and discounts if present
  IF deal_ids IS NOT NULL AND array_length(deal_ids,1) IS NOT NULL THEN
    EXECUTE 'DELETE FROM trusted_partner_discounts WHERE id = ANY($1)' USING deal_ids;
    deleted_count := deleted_count || jsonb_build_object('deals_deleted', true);
  END IF;

  -- Delete processed bills for businesses
  IF business_ids IS NOT NULL AND array_length(business_ids,1) IS NOT NULL THEN
    EXECUTE 'DELETE FROM processed_bills WHERE business_id = ANY($1)' USING business_ids;
    deleted_count := deleted_count || jsonb_build_object('processed_bills_deleted', true);
  END IF;

  -- Delete businesses using detected owner column if available
  IF col_name IS NOT NULL THEN
    sql := format('DELETE FROM public.businesses WHERE %I = $1', col_name);
    EXECUTE sql USING tp_user_id;
    deleted_count := deleted_count || jsonb_build_object('businesses_deleted', true);
  END IF;

  -- Generic helper to delete from tables where column may be named user_id or member_id
  FOR col_name IN SELECT unnest(ARRAY['user_id','member_id','owner_member_id']) LOOP
    EXIT WHEN col_name IS NULL;
    -- trusted_partners
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='trusted_partners' AND column_name = col_name) THEN
      sql := format('DELETE FROM public.trusted_partners WHERE %I = $1', col_name);
      EXECUTE sql USING tp_user_id;
      deleted_count := deleted_count || jsonb_build_object('trusted_partner_record_deleted', true);
      EXIT; -- done for trusted_partners
    END IF;
  END LOOP;

  -- Tables that usually have user_id; try to delete if column exists, otherwise skip
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='paystack_subaccounts' AND column_name='user_id') THEN
    EXECUTE 'DELETE FROM paystack_subaccounts WHERE user_id = $1' USING tp_user_id;
    deleted_count := deleted_count || jsonb_build_object('paystack_subaccounts_deleted', true);
  END IF;

  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='partner_bank_accounts' AND column_name='user_id') THEN
    EXECUTE 'DELETE FROM partner_bank_accounts WHERE user_id = $1' USING tp_user_id;
    deleted_count := deleted_count || jsonb_build_object('bank_accounts_deleted', true);
  END IF;

  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_qr_codes' AND column_name='user_id') THEN
    EXECUTE 'DELETE FROM user_qr_codes WHERE user_id = $1' USING tp_user_id;
    deleted_count := deleted_count || jsonb_build_object('qr_codes_deleted', true);
  END IF;

  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='payments' AND column_name='user_id') THEN
    EXECUTE 'DELETE FROM payments WHERE user_id = $1' USING tp_user_id;
    deleted_count := deleted_count || jsonb_build_object('payments_deleted', true);
  END IF;

  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='notifications' AND column_name='user_id') THEN
    EXECUTE 'DELETE FROM notifications WHERE user_id = $1' USING tp_user_id;
    deleted_count := deleted_count || jsonb_build_object('notifications_deleted', true);
  END IF;

  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='memberships' AND column_name='user_id') THEN
    EXECUTE 'DELETE FROM memberships WHERE user_id = $1' USING tp_user_id;
    deleted_count := deleted_count || jsonb_build_object('memberships_deleted', true);
  END IF;

  -- Finally delete profile if exists
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='id') THEN
    EXECUTE 'DELETE FROM profiles WHERE id = $1' USING tp_user_id;
    deleted_count := deleted_count || jsonb_build_object('profile_deleted', true);
  END IF;

  RETURN deleted_count::json;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to delete trusted partner data: %', SQLERRM;
END;
$$;
