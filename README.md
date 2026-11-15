# local_lekker

A new Flutter project.

## Trusted partner category changes

When an administrator changes a partner's category or special-category flags,
all existing deals must be reviewed before the partner and deals are saved
together. Pending deal requests and unresolved payments must be resolved first.
The new category determines the deal types available during review; cancelling
the review leaves the partner and deals unchanged.

Deploy `20261115100000_review_partner_category_deals.sql` only after testing it
against a disposable database matching production and verifying the deal-payment
migration is present. Release the updated app alongside the migration. Once a
deal has been reviewed, older app versions cannot edit it or submit requests
against it; members and partners must update and reopen the deal. Do not retry
or alter unresolved live payments merely to test category changes.

## Member QR validity

Membership expiry and QR payload expiry are separate. A permanent TP membership
still uses a short-lived QR when displayed. Both member dashboards and TP QR
dialogs use `MemberQrCode` to register a fresh payload before displaying it,
refresh it while open, and refresh after returning from the background.
Expired codes are hidden if connectivity prevents refresh; the member can retry.
Only existing active, unexpired QR records are updated: displaying a QR never
activates membership, extends paid access, or charges a payment.
This client fix requires an app release; existing installations must reopen their
QR after a support-side repair.

## Promotional signup continuation

Completing signup or choosing **Accept & Proceed to Payment** explicitly opens
the membership activation screen for a member who is not yet active. That screen
checks the signed-in email's invitation and presents its introductory price and
free-month period instead of the standard monthly signup option. Ordinary sign-in
still opens browse mode, and active members are not asked to pay again.
An interrupted signup with a verified account can resume by signing in, accepting
terms if required, and opening membership activation. Invitations are not claimed
and free periods do not begin until the introductory payment is verified.

## Server-owned membership billing

Membership payments now use a dedicated `subscription-billing` Edge Function.
Automatic renewal, saved-card manual payment, introductory checkout, callbacks
and reconciliation share one durable obligation per subscription cycle.
Only one caller can change an obligation from `ready` to `submitting`.
An interrupted submission remains unresolved indefinitely: no timer, app restart
or billing-date edit releases it for another debit. Verify the existing reference
instead. Only a **verified terminal failure**, followed by a new member-initiated
payment request, permits a new attempt; the previous reference is retained in
`subscription_billing_failed_attempts`. Automatic failed-payment retries are off.

Verified successful payments atomically update the cycle, membership, profile,
reusable card, QR expiry, renewal history and notification. Cancellation during a submitted
payment is preserved. An in-flight payment cannot be cancelled by deleting a
local lock. Membership access expires server-side after the existing 36-hour
renewal grace; unresolved payments continue to be reconciled, not recharged.
New memberships use calendar months. Existing memberships require an explicit
choice of `30_days` or `calendar_month` when migrated; paid-through dates and
promotion periods are not changed by the migration. Lifetime offers do not renew.
Membership development testing must use Paystack sandbox credentials: client-only
simulation can no longer activate a real membership.
Account deletion is blocked while a payment is in flight; reconcile it first.
Settled-account deletion retains the existing cascading cleanup behaviour.

### Staged rollout for new memberships

Back up the database and deployed payment functions before changing live billing.
Pause renewal and reconciliation jobs for the deployment window. Apply the
deal-payment and server-owned billing migrations together with
[`20261114200000_staged_subscription_billing_rollout.sql`](supabase/migrations/20261114200000_staged_subscription_billing_rollout.sql).
The staged migration restores legacy renewal claims **only** for
`migration_pending` memberships. Server-owned memberships are selected separately
by `server_subscriptions_due_for_renewal` and cannot use a legacy claim.

Inventory Paystack before resuming billing. Mark memberships with verified active
provider subscriptions as `paystack`, including those missing a locally saved SUB
code, so the legacy worker cannot also debit them. Do not change their paid-through
dates, prices, cancellation choices or provider subscriptions.

Configure `SUBSCRIPTION_CHECKOUT_CALLBACK_URL` with the existing hosted payment
return URL. Deploy `subscription-billing`, `scheduled-server-renewal-worker`,
`scheduled-payment-reconciliation-worker`, `paystack-webhook` and `paystack-proxy`.
**Do not replace the deployed legacy `scheduled-renewal-worker` during this stage.**
The separate server worker shares the new renewal implementation without replacing
the legacy deployment. The staged migration creates its cron job disabled, using
the existing renewal schedule, URL and credentials.

Verify checkout, webhook/reconciliation availability, and disjoint renewal
cohorts before enabling `server-subscription-renewal` and resuming the existing
jobs. Test worker authentication without submitting live debits. New memberships
use server-owned billing; existing memberships retain their current renewal path.
Existing members cannot start a second payment through the new endpoint until
their billing is individually reconciled. The guarded proxy rejects legacy
membership checkout/charge requests rather than bypassing that restriction.

### Full migration of existing memberships (not automatic)

Do not deploy the new app independently of its backend.
If the staged rollout is already applied, do not reapply its migrations or replace
the legacy worker. Continue with provider reconciliation and the per-member
ownership migration below; the two disjoint renewal jobs can remain in place.

1. Back up the database and inventory **all** Paystack subscriptions and unresolved
   transactions for each member (not just the locally saved SUB code). Reconcile
   successful charges and preserve paid access before switching billing owners.
2. Pause the local renewal cron job for the maintenance window. Apply
   [the additive deal-payment migration](supabase/migrations/20261112180000_durable_deal_payments.sql)
   before deploying the guarded `paystack-proxy`, which now requires its RPCs.
   The proxy stops legacy membership submissions while preserving ledger-backed
   deal payments. Then apply
   [the billing migration](supabase/migrations/20261104100000_server_owned_subscription_billing.sql).
   Existing rows with a provider code become `paystack`; all other existing
   rows become `migration_pending`, **not** automatically chargeable.
3. Configure `CRON_SECRET`, `PAYSTACK_SECRET_KEY` and
   `SUBSCRIPTION_CHECKOUT_CALLBACK_URL` on the Edge Functions. Use the existing
   hosted auth/payment-return URL for the latter, not an arbitrary client URL.
4. Deploy `subscription-billing`, `scheduled-server-renewal-worker`,
   `scheduled-payment-reconciliation-worker`, `paystack-webhook` and
   `paystack-proxy` together. The proxy blocks legacy subscription submissions
   and plan creation/reactivation, but permits provider cancellation. Existing
   provider-owned renewals retain webhook handling, including `invoice.update`.
5. Release the updated app. Older versions cannot directly extend memberships
   or charge subscriptions through the proxy; show an update-required message
   rather than falling back to an independent charge.
6. For each small migration cohort, disable every provider recurring subscription,
   verify cancellation and resolve any existing invoices/charges. Only then call
   the service-role-only `enable_server_subscription_billing(subscription_id,
   evidence, interval)` RPC, recording the provider verification evidence and
   agreed interval. A missing SUB code is **not** evidence. The function refuses
   migration with a legacy renewal claim or an unresolved ledger payment.
7. Resume the renewal cron and existing 30-minute reconciliation job. Monitor
   `subscription_billing_cycles`, `subscription_billing_audit`, provider
   transactions and worker errors. A cron-authenticated renewal request may include
   `{"user_id":"<authorised-test-member-id>"}` to isolate a test; omitting it
   processes all eligible members. Do not retry live debits merely to test locking.

Rollback means **pause submissions and keep reconciliation running**. Never restore
competing billing paths or automatically re-enable Paystack subscriptions.
Database constraints protect application submissions/fulfilment, not against
provider or bank errors; investigate unmatched legacy charges and unknown outcomes
before permitting any additional debit.

Deal checkout and saved-card payments still use `paystack-proxy`, but the server
now claims a durable `deal_payment_attempts` record before submitting a payment.
Amount, member and partner subaccount come from the approved deal, not the client.
Pending or interrupted payments are verified using the same reference; only a
freshly verified terminal failure permits a new manual attempt. Deal completion,
virtual/partner/member receipts and the member notification commit atomically.
Webhook replay repairs legacy payments only when they identify a specific deal;
it never guesses the member's latest deal. The reconciliation worker also checks
unresolved deal attempts. Existing cron credentials and schedules are retained,
with payment request timeouts extended to 120 seconds.

Subscription operations do not supply partner settlement parameters. Card setup
is bound to its initialized reference and rejects nonreusable authorizations.
Membership and deal Realtime events trigger verification, not a success screen.
The bill-approval entry point uses the existing deal-approval dashboard: partners
approve requests and the member completes payment on their own device.

Validation:

- `node --test supabase/functions/_shared/*.test.mjs` (Node 24): concurrent
  renewals, manual/scheduler races, timeouts, database interruption, webhook
  replay, verified-failure retries and proxy/deal isolation.
- `flutter test test/subscription_billing_service_test.dart test/subscription_renewal_guard_test.dart test/subscription_dates_test.dart test/paystack_service_test.dart test/payment_status_service_test.dart`.
- Run [the billing SQL regressions](supabase/tests/subscription_billing.sql) only
  against a disposable migrated database. They roll back fixtures and make no
  provider requests. Also run the migration and app in staging with sandbox
  Paystack, existing promotion schema and all production RLS policies before rollout.
- Run [the deal-payment SQL regressions](supabase/tests/deal_payments.sql) in the
  same disposable environment. These include unknown outcomes, terminal-failure
  retries, ownership/amount checks, receipt rollback and idempotent finalisation.
  Reduced schema-only fixtures do not replace full staging RLS, triggers or
  native 3DS/sandbox testing.

## Mac download and iOS publishing

Use the [iOS publishing guide](IOS_PUBLISHING_GUIDE.md) to download the clean
source backup on a Mac, restore private client configuration, prepare Xcode
and create a signed App Store build. The GitHub backup is source code, not a
signed IPA or a backup of the live Supabase database.

## Guest browsing and deal savings

New users open on the member dashboard, not the sign-in screen. The guest
sign-up/sign-in banner can be dismissed for that dashboard visit. Guests can
browse deals and partners, filter by area, and use the existing quantity, item
price and restaurant/bill calculators without an account.

Requesting a deal opens the existing sign-up/sign-in screen with the calculated
potential savings. Returning without signing in preserves the calculator inputs
and sends no authorization or payment. After authentication, existing profile,
terms and subscription requirements still apply; browsing does not activate a
membership. Receipts, profile editing and chat require sign-in. Local Sips still
requires an 18+ confirmation; guest confirmations are not written to profiles.
Checkout-priced BOGO savings can only be calculated by the partner at the till,
so those deals show a sign-in action without inventing a savings amount.

Apply [the guest catalogue migration](supabase/migrations/20261101090000_add_guest_business_catalogue.sql)
before releasing this app change. It exposes a read-only, allowlisted business
projection for partners with active deals, not private owner profiles or bank
accounts. Existing authenticated business policies and request/payment guards
are unchanged. Guest discounts are restricted to active offers and keep the
supporting-app capability restriction for restaurant deals.

Run `flutter test test/guest_browsing_test.dart` for guest UI and request-gate
regressions. Run [the database regression script](supabase/tests/guest_browsing.sql)
using `supabase test db` against a disposable database with migrations applied,
never against production.

### Dashboard startup

The opening logo stays visible over the Local Lekker background while the dashboard
restores the saved area and loads partner counts and all active category banners.
The complete dashboard then fades in together, rather than briefly displaying
only Partners. All category banners come from two parallel catalogue queries
(`DiscountService.getHomeCategorySummaries`). Startup checks progress every
5 seconds: slow requests keep running, failed loads retry automatically, and
after 30 seconds a **Try again** prompt appears while checks continue, without
exposing a partial dashboard.

Run `flutter test test/member_home_startup_test.dart` for startup readiness,
area filtering, fade timing and retry regressions.

### Guest conversion tracking

Admins can open **Admin > Overview > Guest browsing & conversion** to see, for
the last 7, 30 or 90 days:

- browsing guests (devices that opened the app without signing in);
- guests who tried to request a deal, and total request attempts;
- which deals and partners guests tried to request, with the savings shown;
- how many requesting guests converted, split into new signups and existing
  members signing in.

Each device gets a random guest id stored locally; no personal data is
collected while browsing. The id is linked to the account on sign-in or sign-up
and then replaced, so later signed-out browsing is tracked separately. Repeat
taps within 30 seconds are ignored and each device is capped at 30 attempts per
hour. A signup that completes on a different device (for example, an email
confirmation link) is not attributed.

Apply [the guest tracking migration](supabase/migrations/20261102090000_add_guest_conversion_tracking.sql)
for this report. Its regression script is
[guest_conversion_tracking.sql](supabase/tests/guest_conversion_tracking.sql).

## Deal image previews

In member deal browsing, tap a deal image to expand it. Tap the enlarged image
again or select **Minimise image** to return to the deal list. Pinch-to-zoom
remains available in the expanded preview.

## Admin sales and engagement reporting

Open **Admin > Overview > Sales, signups & deal engagement** for date-filtered
member and trusted-partner signups, recorded platform payment revenue, completed
deal sales, and per-partner/per-deal engagement. Use search, sorting and the
discussion filter to prioritise partner follow-ups. Expand a partner to see
contact details, individual deals and the existing deal-management entry point.

Apply `supabase/migrations/20261005090000_add_admin_engagement_reporting.sql`
before releasing the updated app. It depends on the earlier role helpers,
business-ID alignment and redirect-deal migrations. Reporting is admin-only;
member event writes use an authenticated RPC, with no direct insert grants.
The migration is additive and does not change the payment lifecycle.

Also apply `supabase/migrations/20261005093000_fix_admin_report_payment_timestamps.sql`.
If reporting was already installed, run only this repair migration; do not rerun
the table-creation migration. The repair replaces the report RPC without
changing tracking tables or payment data. Payment dates use `completed_at`,
then `happened_at` when present, then `created_at`. Both optional timestamp
columns are supported even when absent from older/live payment schemas.

Metric definitions:
- Signups use profile creation dates; activation/terms-accepted counts show the
  **current** status of those signups, not status at the time of signup.
  Older schemas without `partner_terms_accepted` display that status as
  unavailable, not as zero accepted signups.
- Platform revenue uses completed records in `payments`, separately from deal
  sales. It is recorded revenue, not a reconciliation against Paystack.
- Redemptions are `deal_authorizations.status = 'completed'`, counted by
  completion date. Sales use recorded `amount` after discounts, not gross bill
  value. Missing amounts are explicitly flagged. Legacy transactions without a
  completion timestamp use `updated_at`, then `created_at`.
- Request counts use request creation dates and current request statuses;
  they are not a same-period view-to-redemption conversion funnel.
- Views count member opens of a request/detail dialog, deal image preview or
  redirect action, not browsing impressions. Repeated opens are deduplicated in
  fixed 30-minute buckets. Admin/TP activity is excluded by the database.
- Historical views cannot be backfilled. The report shows the tracking start
  date. Existing website/booking redirect clicks remain separate referral
  counts; external purchases/redemptions are not verified.
- Active deals with zero completed redemptions (or zero redirect clicks) are
  discussion prompts, not statistical low-engagement thresholds. Inactive
  deals remain visible for context; partners with no deals are also listed.
- Date selection uses local calendar days with an inclusive end date in the UI;
  the RPC receives UTC timestamps and uses a half-open `[start, end)` interval.

Before deployment, run the focused Flutter tests in
`test/admin_engagement_report_test.dart` and
`test/admin_engagement_screen_test.dart`, and the database regression script
`supabase/tests/admin_engagement_reporting.sql` against a disposable database
with the migrations applied. Never run test fixtures against production.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
