int _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

class GuestDealInterest {
  final String? discountId;
  final String dealName;
  final String? businessName;
  final int attempts;
  final int guests;
  final int convertedGuests;
  final double potentialSavings;

  const GuestDealInterest({
    required this.discountId,
    required this.dealName,
    required this.businessName,
    required this.attempts,
    required this.guests,
    required this.convertedGuests,
    required this.potentialSavings,
  });

  double get conversionRate => guests == 0 ? 0 : convertedGuests / guests;

  factory GuestDealInterest.fromMap(Map<String, dynamic> map) {
    return GuestDealInterest(
      discountId: map['discount_id'] as String?,
      dealName: (map['deal_name'] as String?) ?? 'Removed deal',
      businessName: map['business_name'] as String?,
      attempts: _int(map['attempts']),
      guests: _int(map['guests']),
      convertedGuests: _int(map['converted_guests']),
      potentialSavings: _double(map['potential_savings']),
    );
  }
}

class GuestConversionReport {
  final int browsingGuests;
  final int convertedBrowsingGuests;
  final int requestingGuests;
  final int requestAttempts;
  final int convertedRequestingGuests;
  final int signupConversions;
  final int signinConversions;
  final double potentialSavingsTotal;
  final List<GuestDealInterest> deals;

  const GuestConversionReport({
    required this.browsingGuests,
    required this.convertedBrowsingGuests,
    required this.requestingGuests,
    required this.requestAttempts,
    required this.convertedRequestingGuests,
    required this.signupConversions,
    required this.signinConversions,
    required this.potentialSavingsTotal,
    required this.deals,
  });

  double get requestRate =>
      browsingGuests == 0 ? 0 : requestingGuests / browsingGuests;

  double get requestConversionRate => requestingGuests == 0
      ? 0
      : convertedRequestingGuests / requestingGuests;

  factory GuestConversionReport.fromMap(Map<String, dynamic> map) {
    final deals = (map['deals'] as List?) ?? const [];
    return GuestConversionReport(
      browsingGuests: _int(map['browsing_guests']),
      convertedBrowsingGuests: _int(map['converted_browsing_guests']),
      requestingGuests: _int(map['requesting_guests']),
      requestAttempts: _int(map['request_attempts']),
      convertedRequestingGuests: _int(map['converted_requesting_guests']),
      signupConversions: _int(map['signup_conversions']),
      signinConversions: _int(map['signin_conversions']),
      potentialSavingsTotal: _double(map['potential_savings_total']),
      deals: deals
          .whereType<Map>()
          .map((d) => GuestDealInterest.fromMap(Map<String, dynamic>.from(d)))
          .toList(),
    );
  }
}
