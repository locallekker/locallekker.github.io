# Paystack Subscription Deployment Checklist

## Pre-Deployment (Development/Testing)

### Code Review
- [x] `PaystackService.initializeSubscription()` uses plan codes from environment
- [x] Added `_getPlanCode()` helper method
- [x] Added `checkSubscriptionStatus()` method
- [x] Added `cancelSubscription()` method  
- [x] Added `reactivateSubscription()` method
- [x] Webhook handler processes `subscription.charge` events
- [x] `.env.template` documented with plan code placeholders

### Database
- [ ] Run `supabase/monitoring/payment_health_checks.sql` (read-only); check 7 should show `present = true` for every row
- [ ] Run `add_paystack_subscription_code.sql` in Supabase SQL Editor
- [ ] Verify column exists: `SELECT paystack_subscription_code FROM subscriptions LIMIT 1;`
- [ ] Check index created: `\di idx_subscriptions_paystack_code` (if using psql)

### Environment Configuration
- [ ] Run `dart run tool/check_release_config.dart` (exits non-zero on blocking problems; never prints values)
- [ ] Add `PAYSTACK_MONTHLY_PLAN_CODE=PLN_xxxxx` to `.env`
- [ ] Verify `.env` loaded in app (check logs on startup)
- [ ] Restart Flutter app to load new environment variable

### Paystack Dashboard Setup (Test Mode First)
- [ ] Create test plan with monthly interval
- [ ] Copy test plan code
- [ ] Test payment flow with test card `5060666666666666666`
- [ ] Verify subscription created in Paystack dashboard
- [ ] Check `paystack_subscription_code` saved in database

### Webhook Setup (Test Mode)
- [ ] Deploy edge function: `supabase functions deploy paystack-webhook --no-verify-jwt`
- [ ] Copy webhook URL from deployment output
- [ ] Add webhook in Paystack Test Mode dashboard
- [ ] Enable events: `subscription.create`, `subscription.charge`, `subscription.disable`
- [ ] Test webhook delivery: Send test event from dashboard
- [ ] Check logs: `supabase functions logs paystack-webhook --tail`
- [ ] Verify webhook processed successfully (no errors in logs)

### Integration Testing (Test Mode)
- [ ] New member signup → payment → subscription created
- [ ] Check Paystack dashboard: subscription status = "active"
- [ ] Check database: `paystack_subscription_code` populated
- [ ] Check database: `expires_at` set to 30 days from now
- [ ] Simulate renewal: Use 1-minute test plan, wait, check webhook fired
- [ ] Verify `expires_at` extended by interval period
- [ ] Check notification created for user
- [ ] Test subscription cancellation flow (if UI exists)

---

## Production Deployment

### Paystack Live Mode Setup
- [ ] Switch Paystack dashboard to **Live Mode**
- [ ] Create production plan:
  - Name: `Local Lekker Monthly Membership`
  - Amount: `9900` kobo (R99)
  - Interval: `Monthly`
  - Currency: `ZAR`
- [ ] Copy **production** plan code (starts with `PLN_`)
- [ ] Update `.env` with production plan code
- [ ] Set `PAYSTACK_DEVELOPMENT_MODE=false` in `.env`
- [ ] Verify `PAYSTACK_SECRET_KEY` is production key (starts with `sk_live_`)

### Webhook Production Setup
- [ ] Verify webhook URL points to production Supabase project
- [ ] Add webhook in Paystack **Live Mode** dashboard
- [ ] Enable same events: `subscription.create`, `subscription.charge`, `subscription.disable`
- [ ] Copy webhook secret from Paystack (for signature verification)
- [ ] Add `PAYSTACK_SECRET_KEY` to Supabase edge function secrets:
  ```bash
  supabase secrets set PAYSTACK_SECRET_KEY=sk_live_xxxxx
  ```
- [ ] Redeploy edge function: `supabase functions deploy paystack-webhook --no-verify-jwt`

### Production Testing (Real Money - Use Small Amount or Refund)
- [ ] Create test account with real email
- [ ] Complete signup with real payment card
- [ ] Verify charge appears in Paystack Live dashboard
- [ ] Verify subscription created (status: active)
- [ ] Check database: subscription record created with correct expiry
- [ ] Check webhook logs: `subscription.create` event processed
- [ ] Verify user receives confirmation notification
- [ ] **Optional**: Refund test payment if needed

### Monitoring Setup
- [ ] Set up Supabase monitoring dashboard
- [ ] Configure alerts for edge function errors
- [ ] Set up daily cron job to check for orphaned subscriptions:
  ```sql
  -- Subscriptions expired but still active in Paystack
  SELECT * FROM subscriptions 
  WHERE expires_at < NOW() 
  AND paystack_subscription_code IS NOT NULL;
  ```
- [ ] Monitor Paystack webhook delivery success rate
- [ ] Set up email alerts for failed webhook deliveries

### User Communication
- [ ] Update Terms of Service with subscription terms
- [ ] Add "Subscription" section to member settings/profile
- [ ] Show next billing date in member profile
- [ ] Add "Cancel Subscription" button (if not already present)
- [ ] Email template for successful subscription
- [ ] Email template for renewal confirmation
- [ ] Email template for failed payment (with retry instructions)
- [ ] Email template for subscription cancellation

### App Store Compliance (If Using App/Play Store)
- [ ] Verify compliance with store policies for subscriptions
- [ ] Add subscription details to app store listing
- [ ] Implement proper subscription management UI
- [ ] Add "Restore Subscription" option if needed
- [ ] Test subscription flows on iOS and Android devices

---

## Post-Deployment Monitoring (First 7 Days)

### Daily Checks
- [ ] **Day 1**: Check new subscriptions created successfully
- [ ] **Day 1**: Verify webhook delivery rate > 99%
- [ ] **Day 1**: Check edge function error rate < 0.1%
- [ ] **Day 2-7**: Monitor daily signup conversion rate
- [ ] **Day 2-7**: Check for failed payment notifications
- [ ] **Day 2-7**: Verify `expires_at` dates are correct

### Weekly Checks (First Month)
- [ ] **Week 1**: Review all subscription creation logs
- [ ] **Week 2**: Check for any orphaned subscriptions
- [ ] **Week 3**: Verify webhook signature validation working
- [ ] **Week 4**: Monitor first batch of renewals (30 days after launch)
- [ ] **Week 4**: Check renewal success rate
- [ ] **Week 4**: Verify notifications sent for renewals

### First Renewal Monitoring (Day 30-35)
- [ ] Monitor `subscription.charge` webhook events
- [ ] Verify database updates: `expires_at` extended by 30 days
- [ ] Check payment records created in `payments` table
- [ ] Verify user notifications sent
- [ ] Check for failed renewals and investigate causes
- [ ] Review Paystack dashboard for retry attempts

---

## Rollback Plan (If Issues Occur)

### Critical Issues Requiring Immediate Rollback
- Webhook failing for >50% of events
- Database updates causing data corruption
- Users charged but not receiving access

### Rollback Steps
1. **Disable webhook in Paystack dashboard** (stops new events)
2. **Revert PaystackService code** to use one-time payments:
   ```dart
   // Comment out plan code usage
   // 'plan': planCode,
   ```
3. **Manually process affected subscriptions** via SQL
4. **Issue refunds if necessary** via Paystack dashboard
5. **Communicate with affected users**

### Rollback Validation
- [ ] Verify one-time payments still working
- [ ] Check existing subscriptions not affected
- [ ] Confirm no duplicate charges occurred
- [ ] Review all support tickets related to payments

---

## Success Metrics

### Week 1 Targets
- Subscription creation success rate: > 95%
- Webhook delivery success rate: > 99%
- Edge function error rate: < 1%
- User complaints about payments: 0

### Month 1 Targets
- First renewal success rate: > 90%
- Subscription churn rate: < 5%
- Payment processing time: < 5 seconds
- Average time to resolve payment issues: < 24 hours

### Long-term KPIs
- Monthly recurring revenue (MRR)
- Subscriber growth rate
- Churn rate by cohort
- Average subscription lifetime value
- Payment failure rate and reasons

---

## Contact & Support

### Internal Team
- **Developer**: [Your name/email]
- **DevOps**: [DevOps contact]
- **Customer Support**: [Support team contact]

### External Support
- **Paystack Support**: support@paystack.com
- **Supabase Support**: https://supabase.com/dashboard/support
- **Emergency Hotline**: [Add if available]

### Documentation
- Full setup guide: `PAYSTACK_SUBSCRIPTION_SETUP_GUIDE.md`
- Quick reference: `PAYSTACK_QUICKSTART.md`
- Paystack API docs: https://paystack.com/docs/api/
- Webhook docs: https://paystack.com/docs/payments/webhooks/

---

## Sign-off

- [ ] Code reviewed by: _________________ Date: _______
- [ ] Database changes reviewed by: _________________ Date: _______
- [ ] Security review completed by: _________________ Date: _______
- [ ] Test results approved by: _________________ Date: _______
- [ ] Production deployment approved by: _________________ Date: _______

**Deployment Date**: _______________________
**Deployed By**: _______________________
**Rollback Tested**: Yes / No
**Monitoring Dashboard URL**: _______________________
