import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/models/admin_engagement_report.dart';

import 'admin_engagement_fixtures.dart';

void main() {
  test('Parses numeric RPC totals and nested partner/deal metrics', () {
    final report = AdminEngagementReport.fromMap(reportFixture());
    expect(report.memberSignups, 12);
    expect(report.partnerSignups, 3);
    expect(report.subscriptionSales, 499.5);
    expect(report.dealSales, 161.0);
    expect(
      report.inAppSales + report.posSales + report.otherSales,
      report.dealSales,
    );
    expect(report.missingAmounts, 1);
    expect(report.trackingStartedAt.isUtc, isTrue);
    expect(report.partners.single.reviewDealCount, 1);
    expect(report.partners.single.deals.single.views, 0);
  });

  test('Malformed report is not silently displayed as zero sales', () {
    final map = reportFixture()..remove('deal_sales');
    expect(() => AdminEngagementReport.fromMap(map), throwsA(isA<TypeError>()));
  });

  test('Older schemas explicitly mark unavailable partner terms status', () {
    final report = AdminEngagementReport.fromMap(
      reportFixture()..['ready_partner_signups'] = null,
    );
    expect(report.readyPartnerSignups, isNull);
    expect(report.partnerSignups, 3);
  });

  test('Zero activity and inactive offers have distinct signals', () {
    final quiet = DealEngagement.fromMap(dealFixture());
    final inactive = DealEngagement.fromMap(dealFixture(active: false));
    expect(quiet.engagementSignal, 'No recorded engagement');
    expect(quiet.needsReview, isTrue);
    expect(inactive.engagementSignal, 'Inactive deal');
    expect(inactive.needsReview, isFalse);
  });

  test('Pending and approved requests are not treated as redemptions', () {
    final pending = DealEngagement.fromMap(
      dealFixture(views: 4, requests: 1, pending: 1),
    );
    final approved = DealEngagement.fromMap(
      dealFixture(views: 4, requests: 1, approved: 1),
    );
    expect(pending.engagementSignal, 'Requests awaiting partner approval');
    expect(approved.engagementSignal, 'Approved requests awaiting completion');
    expect(approved.redemptions, 0);
    expect(approved.needsReview, isTrue);
  });

  test('Website and booking referrals do not imply completed sales', () {
    for (final type in ['website_redirect', 'booking_redirect']) {
      final clicked = DealEngagement.fromMap(
        dealFixture(type: type, clicks: 2),
      );
      expect(clicked.engagementSignal, 'External purchases not tracked');
      expect(clicked.needsReview, isFalse);
      expect(clicked.redemptions, 0);
      final unclicked = DealEngagement.fromMap(
        dealFixture(type: type, views: 1),
      );
      expect(unclicked.engagementSignal, 'No redirect clicks');
      expect(unclicked.needsReview, isTrue);
    }
  });

  test('Completed deals no longer need a zero-redemption review', () {
    final completed = DealEngagement.fromMap(dealFixture(redemptions: 2));
    expect(completed.needsReview, isFalse);
    expect(completed.sales, 161);
    expect(completed.engagementSignal, 'Members redeeming');
  });
}
