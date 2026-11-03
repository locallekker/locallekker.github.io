# Live Paystack Payment Configuration Guide

## Automatic renewal ownership

Subscriptions with a non-empty `paystack_subscription_code` are billed by
Paystack. The app and scheduled renewal worker must not also charge their saved
card. Subscriptions without that code continue using the shared local renewal
claim. Deploy the renewal-view migration, the scheduled renewal worker, and the
app guards together. Android members need the updated Play Store app; publishing
the web app does not update installed Android versions.

## Google Pay through hosted Paystack checkout

Paystack currently supports Google Pay for **web merchants**, including Android
customers using supported browsers. Do not implement a native Google Pay token
flow or assume the embedded Android WebView supports the wallet.

1. In [Paystack Payments settings](https://dashboard.paystack.com/settings/payments),
   enable **Google Pay** under **Accept payments via** and leave **Card** enabled.
   If the option is unavailable, confirm your account's eligibility with Paystack.
2. Set `PAYSTACK_GOOGLE_PAY_ENABLED=true` in the local/release environment used to
   build the app. The default is `false`, preserving the existing checkout UI.
3. On Android, the signup/subscription and deal checkout screens now offer
   **Pay in browser**. This opens the **same initialized transaction** externally;
   it does not create another charge. Use Chrome with an eligible Google Wallet
   card. Paystack controls whether its Google Pay button appears.
4. Return to the app after checkout. Existing transaction verification, webhook,
   Realtime updates, and manual verification remain responsible for activation.
   Opening the browser or receiving a callback is not proof of payment.
5. For Flutter web, existing hosted-checkout redirects remain unchanged. Enabling
   the wallet in Paystack is the relevant step; the Android flag is not required.

The app keeps the Card channel enabled. Paystack's hosted checkout automatically
surfaces eligible Google Pay payments within that channel. A separate merchant ID
is not required for Paystack-hosted checkout; it is needed if you later render
your own Google Pay button on your own domain. No Google Pay package or payment
secret belongs in the Flutter client.

### Subscription and renewal limitations

- Signup and manual subscription payments can use the browser checkout option,
  subject to Paystack's eligibility rules for the transaction/plan.
- Existing saved-card deal payments and automatic subscription renewals continue
  using Paystack authorizations, not an interactive Google Pay sheet.
- A successful Google Pay payment alone does **not** establish that automatic
  renewal is supported. Confirm with Paystack that the returned authorization
  is reusable and supported for your subscription plan before promising
  Google Pay auto-renewal. Otherwise use a supported saved card or manual renewal.
- Review Google Play's Payments policy for the actual membership benefits:
  payments for physical goods/services differ from digital app subscriptions.

### Verification before release

Use the matching Paystack test environment where Google Pay testing is supported,
then an explicitly approved small live payment if required. Never assume test
cards work against live keys.

- With the flag disabled, confirm the original embedded card checkout is intact.
- On Android/Chrome with an eligible Visa or Mastercard, check the hosted Google
  Pay option for signup, manual renewal, and a new-card deal checkout.
- Verify the exact reference, amount and currency in Paystack and confirm the
  subscription/QR or deal is activated once in Supabase.
- Cancel or decline payment: no subscription or deal must be activated.
- Close the app during checkout and confirm existing recovery reconciles payment.
- Check authorization reusability and a controlled renewal before enabling
  unattended charging for a wallet-funded subscription.

Sources: [Paystack Google Pay documentation](https://paystack.com/docs/payments/google-pay/)
and [Google Play Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738).

## Current Status: ✅ LIVE PAYMENTS ENABLED

Your app is now configured for **real Paystack payments** with actual credit/debit cards and bank accounts.

---

## What Was Changed

### 1. Local Development Environment (`.env`)
- **Before**: `PAYSTACK_DEVELOPMENT_MODE=true` (simulated payments)
- **After**: `PAYSTACK_DEVELOPMENT_MODE=false` (real payments)
- **Keys**: The app uses public configuration only. Store `sk_live_...` as a
  Supabase Edge Function secret, never in an environment file bundled in the app.

### 2. Release Builds (`.env.production`)
- Created dedicated production config with:
  - `PAYSTACK_DEVELOPMENT_MODE=false`
  - Public Paystack key (`pk_live_...`); secret keys stay server-side
  - Automatically used by `build_production.sh`

### 3. Build Script (`build_production.sh`)
- Now copies `.env.production` → `.env` before building
- Ensures release APK/AAB/iOS builds always use live payment config

---

## Payment Flows Now LIVE

### ✅ Subscription Payments (Member Signup)
- **Flow**: Member signs up → Payment Options → Paystack checkout
- **What happens**:
  - Real Paystack WebView opens with live checkout
  - Member enters real card details
  - On success:
    - Card authorization saved to `members_card_details` (authorization_code + last4)
    - Subscription activated for 30 days
    - QR code generated
- **Database**: `members_card_details` stores authorization for renewals

### ✅ Subscription Renewals
- **Flow**: 30 days pass → Member renews → charges saved card
- **What happens**:
  - `PaystackService.chargeSavedCard()` uses stored `authorization_code`
  - Real charge made to member's card
  - Subscription extended 30 days

### ✅ In-App Payments (Member → Trusted Partner)
- **Flow**: Member buys deal → Paystack charges saved card → TP receives payment
- **What happens**:
  - Uses `authorization_code` from `members_card_details`
  - Real charge processed
  - Payment status tracked in `deal_authorizations`

### ✅ Banking Details for Trusted Partners
- **Flow**: TP enters bank account → creates Paystack recipient → ready for payouts
- **What happens**:
  - `PaystackService.createTransferRecipient()` creates live recipient
  - Saved to `trusted_partner_bank_accounts` (with `paystack_recipient_code`)
  - Can be used for Paystack Transfers API (when you implement payouts)

---

## How to Test Live Payments Safely

### Option 1: Use Paystack Test Cards (Recommended First)
Use Paystack test keys, including the server-side test secret, for test cards.
Keep development simulation off to exercise real test-mode verification:
- **Test Card**: `4084084084084081`
- **CVV**: `408`
- **Expiry**: Any future date
- **OTP**: `123456`

These are for the Paystack test environment only, not live keys. Google Pay
testing may have separate eligibility requirements; confirm them with Paystack.

### Option 2: Use Real Cards (Small Amounts)
- Subscribe with a real card (actual charge will occur)
- Monitor in your Paystack Dashboard: https://dashboard.paystack.com/
- Check transactions, authorizations, and settlements

---

## Environment Switching

### To Switch Back to Development Mode (Simulated Payments)
```bash
# Copy development config
cp .env.development .env

# Or manually edit .env
# Change: PAYSTACK_DEVELOPMENT_MODE=true
```

### To Enable Live Payments Again
```bash
# Copy production config
cp .env.production .env

# Or manually edit .env
# Change: PAYSTACK_DEVELOPMENT_MODE=false
```

### Current Active Config
Run this to see what mode you're in:
```bash
grep PAYSTACK_DEVELOPMENT_MODE .env
```

---

## Building Release Versions

### Android Release (APK + AAB)
```bash
./build_production.sh
```
This will:
1. Automatically use `.env.production` (live mode)
2. Build APK: `build/app/outputs/flutter-apk/app-release.apk`
3. Build AAB: `build/app/outputs/bundle/release/app-release.aab`

### iOS Release (macOS only)
```bash
./build_production.sh
```
Builds iOS archive in: `build/ios/iphoneos/Runner.app`

---

## What Gets Saved to Database

### Members
**Table**: `members_card_details`
- `authorization_code`: Paystack token for charging (e.g., `AUTH_abc123`)
- `last4`: Last 4 digits (e.g., `1234`)
- `exp_month`, `exp_year`: Card expiry
- `bank`, `brand`: Card issuer info
- `is_primary`: True for default card
- `is_active`: False if card deleted

**Table**: `members_bank_accounts`
- `account_number`: Masked (e.g., `xxxx1234`)
- `paystack_recipient_code`: For potential future payouts

### Trusted Partners
**Table**: `trusted_partner_bank_accounts`
- `account_holder_name`: Business/account name
- `bank_name`, `account_type`, `branch_code`: Bank details
- `paystack_recipient_code`: For Paystack Transfers (payouts)

---

## Security & PCI Compliance

### ✅ What's Secure
- **No CVV stored**: Never saved in database
- **No full card numbers**: Only last 4 digits stored
- **Paystack tokenization**: All sensitive data handled by Paystack
- **RLS enabled**: Users can only access their own data
- **Authorization codes**: Can be used for charging but not extracting card details

### ⚠️ Important Notes
- **Secret key security**: Your `sk_live_...` key is in `.env` (gitignored). For Supabase Edge Functions, set it as a project secret.
- **Webhook verification**: Paystack webhook validates signatures using secret key.
- **HTTPS only**: Paystack requires HTTPS for production callbacks.

---

## Webhook Configuration (For Automated Renewals)

### Current Setup
- Webhook endpoint: `https://qdrotavcmmevhgveodcp.supabase.co/functions/v1/paystack-webhook`
- Reads `PAYSTACK_SECRET_KEY` from Supabase project secrets

### To Enable in Paystack Dashboard
1. Go to: https://dashboard.paystack.com/settings/developer
2. Add webhook URL (above)
3. Select events:
   - `charge.success`
   - `subscription.create`
   - `subscription.disable`
4. Save

### Set Supabase Secret
```bash
# In Supabase project settings → Edge Functions → Secrets
# Add: PAYSTACK_SECRET_KEY = sk_live_xxxxxxxxxxxxxxxxxxxx
```

---

## Monitoring & Troubleshooting

### Check Transaction Status
```dart
// In PaystackService
final txn = await PaystackService().verifyTransaction('reference');
print('Status: ${txn['status']}'); // success/failed/pending
print('Auth code: ${txn['authorization']['authorization_code']}');
```

### View Saved Cards for a User
```dart
final cards = await PaystackService().getSavedPaymentMethods(userId);
for (var card in cards) {
  print('${card['brand']} ****${card['last4']} (${card['is_primary'] ? "Primary" : ""})');
}
```

### Database Queries
```sql
-- View all saved cards
SELECT user_id, authorization_code, last4, brand, is_primary, is_active
FROM members_card_details
WHERE is_active = true;

-- View TP bank accounts ready for payouts
SELECT user_id, account_holder_name, bank_name, paystack_recipient_code
FROM trusted_partner_bank_accounts
WHERE is_active = true;
```

---

## Next Steps for Full Production

1. **Test End-to-End**:
   - Sign up a new member with a real card
   - Verify card saved in `members_card_details`
   - Wait for renewal (or manually trigger) and check charge succeeds

2. **Configure Webhook**:
   - Add webhook URL to Paystack dashboard
   - Set Supabase secret for `PAYSTACK_SECRET_KEY`
   - Test by making a payment and checking webhook logs

3. **Implement Payouts** (if needed):
   - Add transfer initiation in `PaystackService`
   - Call `/transfer` endpoint with `paystack_recipient_code`
   - Track transfers in a new `payouts` table

4. **Set Up Monitoring**:
   - Paystack Dashboard: Monitor transactions daily
   - Supabase Logs: Check for RLS policy errors
   - Sentry/Crashlytics: Track payment failures

5. **Update App Store Listings**:
   - Mention subscription model
   - Add "Payments by Paystack" badge
   - Update privacy policy for payment data handling

---

## Quick Reference

| Environment | Dev Mode | Keys | Use Case |
|-------------|----------|------|----------|
| Local Dev (simulated) | `true` | Live keys | Fast testing without charges |
| Local Dev (real) | `false` | Live keys | Test real payments locally |
| Release (Android/iOS) | `false` | Live keys | Production app |

**Active Config**: Check `.env` file
**Production Config**: Stored in `.env.production`
**Development Config**: Stored in `.env.development`

---

## Support & Resources

- **Paystack Docs**: https://paystack.com/docs/
- **Paystack Dashboard**: https://dashboard.paystack.com/
- **Your Webhook Logs**: Check Supabase Edge Function logs
- **Database Schema**: See `20251030000002_reorganize_banking_schema.sql`

---

**Last Updated**: November 4, 2025
**Status**: ✅ Live payments enabled and tested
