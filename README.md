# local_lekker

A new Flutter project.

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
