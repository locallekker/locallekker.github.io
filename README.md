# local_lekker

A new Flutter project.

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
