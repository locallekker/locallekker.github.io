class EngagementMetrics {
  final int views;
  final int viewers;
  final int redirectClicks;
  final int requests;
  final int redemptions;
  final double sales;
  final int missingAmounts;

  EngagementMetrics.fromMap(Map<String, dynamic> map)
    : views = (map['views'] as num).toInt(),
      viewers = (map['viewers'] as num).toInt(),
      redirectClicks = (map['redirect_clicks'] as num).toInt(),
      requests = (map['requests'] as num).toInt(),
      redemptions = (map['redemptions'] as num).toInt(),
      sales = (map['sales'] as num).toDouble(),
      missingAmounts = (map['missing_amounts'] as num).toInt();
}

class DealEngagement extends EngagementMetrics {
  final String id;
  final String name;
  final String? type;
  final bool active;
  final int pending;
  final int approved;
  final int rejected;
  final int redeemingMembers;

  DealEngagement.fromMap(super.map)
    : id = map['id'] as String,
      name = map['name'] as String,
      type = map['deal_type'] as String?,
      active = map['is_active'] == true,
      pending = (map['pending'] as num).toInt(),
      approved = (map['approved'] as num).toInt(),
      rejected = (map['rejected'] as num).toInt(),
      redeemingMembers = (map['redeeming_members'] as num).toInt(),
      super.fromMap();

  bool get isRedirect =>
      type == 'website_redirect' || type == 'booking_redirect';

  String get engagementSignal {
    if (!active) return 'Inactive deal';
    if (views == 0 &&
        requests == 0 &&
        redemptions == 0 &&
        redirectClicks == 0) {
      return 'No recorded engagement';
    }
    if (isRedirect) {
      return redirectClicks == 0
          ? 'No redirect clicks'
          : 'External purchases not tracked';
    }
    if (redemptions == 0) {
      if (approved > 0) return 'Approved requests awaiting completion';
      if (pending > 0) return 'Requests awaiting partner approval';
      return 'No completed redemptions';
    }
    return 'Members redeeming';
  }

  bool get needsReview =>
      active && (isRedirect ? redirectClicks == 0 : redemptions == 0);
}

class PartnerEngagement extends EngagementMetrics {
  final String id;
  final String name;
  final String city;
  final String email;
  final String contact;
  final List<DealEngagement> deals;

  PartnerEngagement.fromMap(super.map)
    : id = map['partner_id'] as String,
      name = map['name'] as String,
      city = map['city'] as String,
      email = map['email'] as String,
      contact = map['contact'] as String,
      deals = (map['deals'] as List)
          .map(
            (e) => DealEngagement.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      super.fromMap();

  int get reviewDealCount => deals.where((d) => d.needsReview).length;
}

class AdminEngagementReport {
  final DateTime trackingStartedAt;
  final int memberSignups;
  final int partnerSignups;
  final int activeMemberSignups;
  final int? readyPartnerSignups;
  final int subscriptionPayments;
  final double subscriptionSales;
  final int redemptions;
  final double dealSales;
  final double inAppSales;
  final double posSales;
  final double otherSales;
  final int missingAmounts;
  final int views;
  final int viewers;
  final List<PartnerEngagement> partners;

  AdminEngagementReport.fromMap(Map<String, dynamic> map)
    : trackingStartedAt = DateTime.parse(map['tracking_started_at'] as String),
      memberSignups = (map['member_signups'] as num).toInt(),
      partnerSignups = (map['partner_signups'] as num).toInt(),
      activeMemberSignups = (map['active_member_signups'] as num).toInt(),
      readyPartnerSignups = (map['ready_partner_signups'] as num?)?.toInt(),
      subscriptionPayments = (map['subscription_payments'] as num).toInt(),
      subscriptionSales = (map['subscription_sales'] as num).toDouble(),
      redemptions = (map['redemptions'] as num).toInt(),
      dealSales = (map['deal_sales'] as num).toDouble(),
      inAppSales = (map['in_app_sales'] as num).toDouble(),
      posSales = (map['pos_sales'] as num).toDouble(),
      otherSales = (map['other_sales'] as num).toDouble(),
      missingAmounts = (map['missing_amounts'] as num).toInt(),
      views = (map['views'] as num).toInt(),
      viewers = (map['viewers'] as num).toInt(),
      partners = (map['partners'] as List)
          .map(
            (e) =>
                PartnerEngagement.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
}
