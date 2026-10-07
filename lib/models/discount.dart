class Discount {
  /// Admin-only deal that sends members to the partner's website.
  static const String websiteRedirectType = 'website_redirect';

  /// Admin-only deal (Locally Active category) that sends members to an
  /// external booking page (e.g. Playtomic) stored in custom_data.
  static const String bookingRedirectType = 'booking_redirect';

  final String id;
  final String trustedPartnerId;
  final String name;
  final String description;
  final String itemName;
  final double itemPrice;
  final double percentage;
  final double? fixedAmount;
  final String
  dealType; // standard | bill_discount | once_off | weight | buy_get | percent_item
  final Map<String, dynamic>? customData; // type-specific payload
  final bool
  requiresManualPrice; // when true member must supply price at request time
  final bool isActive;
  final bool isWeightBased;
  final bool isBillDiscount;
  final bool isOnceOff;
  final Map<String, dynamic>? billDiscountData;
  final String? imageUrl;
  final Map<String, dynamic>? scheduleData;
  final String dealCategory;
  final bool offersDelivery;
  final String? city; // City where this deal is available
  final DateTime createdAt;
  final DateTime updatedAt;

  Discount({
    required this.id,
    required this.trustedPartnerId,
    required this.name,
    required this.description,
    required this.itemName,
    required this.itemPrice,
    required this.percentage,
    this.fixedAmount,
    this.dealType = 'standard',
    this.customData,
    this.requiresManualPrice = false,
    required this.isActive,
    this.isWeightBased = false,
    this.isBillDiscount = false,
    this.isOnceOff = false,
    this.billDiscountData,
    this.imageUrl,
    this.scheduleData,
    this.dealCategory = 'Other',
    this.offersDelivery = false,
    this.city,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Discount.fromJson(Map<String, dynamic> json) {
    return Discount(
      id: (json['id'] as String?) ?? '',
      trustedPartnerId: (json['trusted_partner_id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Unnamed Deal',
      description: (json['description'] as String?) ?? '',
      itemName: (json['item_name'] as String?) ?? 'Item',
      itemPrice: (json['item_price'] as num?)?.toDouble() ?? 0.0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
      fixedAmount: json['fixed_amount'] != null
          ? (json['fixed_amount'] as num).toDouble()
          : null,
      dealType: (json['deal_type'] as String?) ?? 'standard',
      customData: json['custom_data'] != null
          ? Map<String, dynamic>.from(
              json['custom_data'] as Map<String, dynamic>,
            )
          : null,
      requiresManualPrice: (json['requires_manual_price'] as bool?) ?? false,
      isActive: (json['is_active'] as bool?) ?? true,
      isWeightBased: (json['is_weight_based'] as bool?) ?? false,
      isBillDiscount: (json['is_bill_discount'] as bool?) ?? false,
      isOnceOff: (json['is_once_off'] as bool?) ?? false,
      billDiscountData: json['bill_discount_data'] as Map<String, dynamic>?,
      imageUrl: json['image_url'] as String?,
      scheduleData: json['schedule_data'] as Map<String, dynamic>?,
      dealCategory: (json['deal_category'] as String?) ?? 'Other',
      offersDelivery: (json['offers_delivery'] as bool?) ?? false,
      city: json['city'] as String?,
      createdAt: DateTime.parse(
        (json['created_at'] as String?) ??
            DateTime.now().toUtc().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        (json['updated_at'] as String?) ??
            DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trusted_partner_id': trustedPartnerId,
      'name': name,
      'description': description,
      'item_name': itemName,
      'item_price': itemPrice,
      'percentage': percentage,
      'fixed_amount': fixedAmount,
      'deal_type': dealType,
      'custom_data': customData,
      'requires_manual_price': requiresManualPrice,
      'is_active': isActive,
      'is_weight_based': isWeightBased,
      'is_bill_discount': isBillDiscount,
      'is_once_off': isOnceOff,
      'bill_discount_data': billDiscountData,
      'image_url': imageUrl,
      'schedule_data': scheduleData,
      'deal_category': dealCategory,
      'offers_delivery': offersDelivery,
      'city': city,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isBuyGet {
    final type = dealType.trim().toLowerCase();
    return type == 'buy_get' || type == 'buyget';
  }

  bool get isPercentItem {
    final type = dealType.trim().toLowerCase();
    return type == 'percent_item' || type == 'percentitem';
  }

  /// Item sold at its normal price, with delivery included at no charge.
  bool get isFreeDelivery {
    final type = dealType.trim().toLowerCase();
    return type == 'free_delivery' || type == 'freedelivery';
  }

  bool get isWebsiteRedirect =>
      dealType.trim().toLowerCase() == websiteRedirectType;

  bool get isBookingRedirect =>
      dealType.trim().toLowerCase() == bookingRedirectType;

  String? get bookingUrl => customData?['booking_url'] as String?;

  double get dealPrice {
    // Type-aware pricing
    if (isBuyGet) {
      // For buyGet, the deal price is just the buy item price (member pays for buy item, gets free item free)
      final buyPrice = customData?['buy_item_price'];
      if (buyPrice is num) return buyPrice.toDouble();
      // Fallback to itemPrice if customData not available
      return itemPrice;
    }

    if (isPercentItem && requiresManualPrice) {
      // Price entered later by member; return placeholder
      return 0.0;
    }

    if (fixedAmount != null && fixedAmount! > 0) {
      return itemPrice - fixedAmount!;
    } else {
      return itemPrice * (1 - percentage / 100);
    }
  }

  double get savings {
    if (isBuyGet) {
      // For buyGet, savings is the value of the free item
      final freeValue = customData?['free_item_value'];
      if (freeValue is num) return freeValue.toDouble();
      // Fallback calculation
      return fixedAmount ?? 0.0;
    }

    if (isPercentItem && requiresManualPrice) {
      return 0.0;
    }

    return itemPrice - dealPrice;
  }

  String get discountDisplay {
    if (isWebsiteRedirect) {
      return 'Visit website';
    }

    if (isBookingRedirect) {
      return 'Book now';
    }

    if (isFreeDelivery) {
      return 'Free delivery';
    }

    if (dealType == 'buy_get') {
      final buyName = customData?['buy_item_name'] ?? itemName;
      final freeName = customData?['free_item_name'] ?? 'bonus item';
      return 'Buy $buyName get $freeName';
    }

    if (dealType == 'percent_item') {
      return '${percentage.toStringAsFixed(0)}% off (enter price)';
    }

    if (fixedAmount != null && fixedAmount! > 0) {
      return 'R${fixedAmount!.toStringAsFixed(2)} off';
    } else {
      return '${percentage.toStringAsFixed(0)}% off';
    }
  }
}
