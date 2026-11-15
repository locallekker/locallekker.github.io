-- Disposable migrated database only. No provider requests are made.
BEGIN;
SELECT '1..1' AS tap;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
  ('de100000-0000-0000-0000-000000000001','deal-member@example.test','{}'),
  ('de100000-0000-0000-0000-000000000002','deal-partner@example.test','{}');
INSERT INTO public.profiles(id,email,name,surname,role) VALUES
  ('de100000-0000-0000-0000-000000000001','deal-member@example.test','Deal','Member','member'),
  ('de100000-0000-0000-0000-000000000002','deal-partner@example.test','Deal','Partner','trusted_partner')
ON CONFLICT(id) DO UPDATE SET email=EXCLUDED.email;

DO $$
DECLARE
  v_member uuid := 'de100000-0000-0000-0000-000000000001';
  v_partner uuid := 'de100000-0000-0000-0000-000000000002';
  v_business uuid := gen_random_uuid();
  v_discount uuid := gen_random_uuid();
  v_deal uuid := gen_random_uuid();
  v_other_deal uuid := gen_random_uuid();
  v_payment jsonb;
  v_again jsonb;
  v_result jsonb;
BEGIN
  INSERT INTO public.businesses(id,name,owner_member_id) VALUES(v_business,'Deal fixture',v_partner);
  INSERT INTO public.trusted_partner_discounts(id,business_id,trusted_partner_id,name,item_name,item_price,percentage)
    VALUES(v_discount,v_business,v_partner,'Deal fixture','Fixture',100,10);
  INSERT INTO public.trusted_partner_bank_accounts(user_id,account_holder_name,account_type,branch_code,
    subaccount_code,is_active,subaccount_active)
    VALUES(v_partner,'Fixture','checking','000000','ACCT_fixture',true,true);
  INSERT INTO public.deal_authorizations(id,member_id,business_id,discount_id,amount,status,payment_method)
    VALUES(v_deal,v_member,v_business,v_discount,90,'approved','in_app');
  BEGIN
    PERFORM public.prepare_deal_payment(v_partner,v_deal);
    RAISE EXCEPTION 'A different member could prepare this payment';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Deal does not belong to this member' THEN RAISE; END IF;
  END;
  v_payment := public.prepare_deal_payment(v_member,v_deal);
  IF (v_payment->>'amount_cents')::integer <> 9000 OR v_payment->>'subaccount_code' <> 'ACCT_fixture' THEN
    RAISE EXCEPTION 'Deal amount or settlement is not authoritative';
  END IF;
  BEGIN
    PERFORM public.finalise_deal_payment(v_deal,v_member,v_payment->>'reference','fixture-tx',9000,'ZAR',now());
    RAISE EXCEPTION 'Unsubmitted payment completed a deal';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Payment has not been submitted' THEN RAISE; END IF;
  END;
  IF NOT public.claim_deal_payment((v_payment->>'id')::uuid) THEN RAISE EXCEPTION 'First claim failed'; END IF;
  IF public.claim_deal_payment((v_payment->>'id')::uuid) THEN RAISE EXCEPTION 'Duplicate claim succeeded'; END IF;
  PERFORM public.record_deal_payment_outcome(v_payment->>'reference','unknown');
  v_again := public.prepare_deal_payment(v_member,v_deal);
  IF v_again->>'reference' <> v_payment->>'reference' THEN RAISE EXCEPTION 'Unknown payment was replaced'; END IF;
  BEGIN
    PERFORM public.retry_deal_payment((v_payment->>'id')::uuid,v_payment->>'reference');
    RAISE EXCEPTION 'Uncertain payment could be retried';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Verify the previous terminal failure before retrying' THEN RAISE; END IF;
  END;
  PERFORM public.record_deal_payment_outcome(v_payment->>'reference','failed');
  v_again := public.retry_deal_payment((v_payment->>'id')::uuid,v_payment->>'reference');
  IF v_again->>'reference' = v_payment->>'reference' THEN RAISE EXCEPTION 'Verified failure reused its reference'; END IF;
  IF public.retry_deal_payment((v_payment->>'id')::uuid,v_payment->>'reference')->>'reference'
      <> v_again->>'reference' THEN RAISE EXCEPTION 'Concurrent retry created another charge'; END IF;
  v_payment := v_again;
  IF NOT public.claim_deal_payment((v_payment->>'id')::uuid) THEN RAISE EXCEPTION 'Retry claim failed'; END IF;
  BEGIN
    PERFORM public.finalise_deal_payment(v_deal,v_member,v_payment->>'reference','fixture-tx',100,'ZAR',now());
    RAISE EXCEPTION 'Wrong amount completed a deal';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Payment does not match this deal' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.finalise_deal_payment(v_deal,v_partner,v_payment->>'reference','fixture-tx',9000,'ZAR',now());
    RAISE EXCEPTION 'Wrong member completed a deal';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Payment does not match this deal' THEN RAISE; END IF;
  END;
  INSERT INTO public.deal_authorizations(id,member_id,business_id,discount_id,amount,status,payment_method)
    VALUES(v_other_deal,v_member,v_business,v_discount,90,'approved','in_app');
  INSERT INTO public.virtual_receipts(deal_authorization_id,receipt_number,receipt_data)
    VALUES(v_other_deal,'RCP-'||v_deal::text,'{}');
  BEGIN
    PERFORM public.finalise_deal_payment(v_deal,v_member,v_payment->>'reference','fixture-tx',9000,'ZAR',now());
    RAISE EXCEPTION 'Receipt failure did not interrupt completion';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  IF (SELECT status FROM public.deal_authorizations WHERE id=v_deal) <> 'approved'
    OR (SELECT state FROM public.deal_payment_attempts WHERE id=(v_payment->>'id')::uuid) = 'paid' THEN
    RAISE EXCEPTION 'Receipt failure left a partially completed payment';
  END IF;
  DELETE FROM public.virtual_receipts WHERE deal_authorization_id=v_other_deal;
  DELETE FROM public.deal_authorizations WHERE id=v_other_deal;
  v_result := public.finalise_deal_payment(v_deal,v_member,v_payment->>'reference','fixture-tx',9000,'ZAR',now());
  IF (v_result->>'applied')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'Deal was not applied'; END IF;
  v_result := public.finalise_deal_payment(v_deal,v_member,v_payment->>'reference','fixture-tx',9000,'ZAR',now());
  IF (v_result->>'applied')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'Deal was applied twice'; END IF;
  BEGIN
    PERFORM public.finalise_deal_payment(v_deal,v_member,v_payment->>'reference','different-tx',9000,'ZAR',now());
    RAISE EXCEPTION 'Replay accepted a conflicting provider identity';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Conflicting provider transaction' THEN RAISE; END IF;
  END;
  IF (SELECT count(*) FROM public.deal_receipts WHERE deal_authorization_id=v_deal) <> 1
      OR (SELECT count(*) FROM public.virtual_receipts WHERE deal_authorization_id=v_deal) <> 1
      OR (SELECT count(*) FROM public.member_receipts WHERE member_id=v_member) <> 1 THEN
    RAISE EXCEPTION 'Receipt sets were not committed once';
  END IF;
  IF (SELECT status FROM public.deal_authorizations WHERE id=v_deal) <> 'completed'
      OR (SELECT state FROM public.deal_payment_attempts WHERE id=(v_payment->>'id')::uuid) <> 'paid' THEN
    RAISE EXCEPTION 'Payment and fulfilment were not committed together';
  END IF;
  IF has_function_privilege('authenticated','public.claim_deal_payment(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'Member can bypass the payment server';
  END IF;
END;
$$;
SELECT 'ok 1 - deal claims, uncertain outcomes, retries and atomic receipts' AS tap;
ROLLBACK;
