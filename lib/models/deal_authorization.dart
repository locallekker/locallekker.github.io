import 'profile.dart';
import 'discount.dart';

class DealAuthorization {
  final String id;
  final String memberId;
  final String trustedPartnerId;
  final String discountId;
  final String status; // pending, approved, rejected, completed
  final String authorizationType; // in_store, online
  final String? paymentMethod; // in_app, pos
  final double? amount;
  final double? memberEnteredPrice; // member-provided base price for manual deals
  final double? appliedDiscountAmount; // savings applied at request time
  final String? dealType; // snapshot of deal type at request time
  final Map<String, dynamic>? dealSnapshot; // snapshot of deal data
  final String? notes;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? approvedAt;
  final DateTime? paymentCompletedAt;
  final DateTime? completedAt;

  // The actual business UUID (from deal_authorizations.business_id)
  final String? businessId;

  // Related data (populated by joins)
  final Profile? member;
  final Map<String, dynamic>? trustedPartner;
  final Discount? discount;
  final String? businessName;

  DealAuthorization({
    required this.id,
    required this.memberId,
    required this.trustedPartnerId,
    required this.discountId,
    required this.status,
    required this.authorizationType,
    this.paymentMethod,
    this.amount,
    this.memberEnteredPrice,
    this.appliedDiscountAmount,
    this.dealType,
    this.dealSnapshot,
    this.notes,
    this.rejectionReason,
    required this.createdAt,
    required this.updatedAt,
    this.approvedAt,
    this.paymentCompletedAt,
    this.completedAt,
    this.businessId,
    this.member,
    this.trustedPartner,
    this.discount,
    this.businessName,
  });

  factory DealAuthorization.fromJson(Map<String, dynamic> json) {
    // Handle required fields with proper null safety
    final id = json['id'] as String?;
    final memberId = json['member_id'] as String?;

    // Try multiple sources for trusted_partner_id
    var trustedPartnerId =
        (json['trusted_partner_id'] ?? json['business_id']) as String?;

    // If not found, try to extract from nested discount
    if (trustedPartnerId == null && json['trusted_partner_discounts'] != null) {
      trustedPartnerId =
          (json['trusted_partner_discounts']
                  as Map<String, dynamic>)['trusted_partner_id']
              as String?;
    }

    final discountId = json['discount_id'] as String?;

    // Throw descriptive error if critical fields are missing
    if (id == null) throw Exception('Deal authorization missing id');
    if (trustedPartnerId == null) {
      throw Exception(
        'Deal authorization missing trusted_partner_id/business_id',
      );
    }
    // member_id and discount_id may be null for legacy or partially-created
    // records (e.g. once-off / bill discount requests). We tolerate this so
    // the trusted partner can still see and act on the request rather than
    // the whole list failing to load.
    final safeMemberId = memberId ?? '';
    final safeDiscountId = discountId ?? '';

    // Extract business_id separately (distinct from trusted_partner_id)
    final businessId = json['business_id'] as String?;

    return DealAuthorization(
      id: id,
      memberId: safeMemberId,
      trustedPartnerId: trustedPartnerId,
      discountId: safeDiscountId,
      status: json['status'] as String? ?? 'pending',
      authorizationType: json['authorization_type'] as String? ?? 'in_store',
      paymentMethod: json['payment_method'] as String?,
      amount: json['amount'] != null
          ? (json['amount'] as num).toDouble()
          : null,
        memberEnteredPrice: json['member_entered_price'] != null
          ? (json['member_entered_price'] as num).toDouble()
          : null,
        appliedDiscountAmount: json['applied_discount_amount'] != null
          ? (json['applied_discount_amount'] as num).toDouble()
          : null,
        dealType: json['deal_type'] as String?,
        dealSnapshot: json['deal_snapshot'] != null
            ? Map<String, dynamic>.from(
                json['deal_snapshot'] as Map<String, dynamic>,
              )
            : null,
      notes: json['notes'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      paymentCompletedAt: json['payment_completed_at'] != null
          ? DateTime.parse(json['payment_completed_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      businessId: businessId,
      // Support both 'member' and 'profiles' keys (Supabase foreign key naming)
      member: json['member'] != null
          ? Profile.fromJson(json['member'] as Map<String, dynamic>)
          : (json['profiles'] != null
                ? Profile.fromJson(json['profiles'] as Map<String, dynamic>)
                : null),
      trustedPartner: json['trusted_partner'] as Map<String, dynamic>?,
      // Support both 'discount' and 'trusted_partner_discounts' keys
      discount: json['discount'] != null
          ? Discount.fromJson(json['discount'] as Map<String, dynamic>)
          : (json['trusted_partner_discounts'] != null
                ? Discount.fromJson(
                    json['trusted_partner_discounts'] as Map<String, dynamic>,
                  )
                : null),
      // Prefer the business linked via the discount, but fall back to the
      // business embedded directly off deal_authorizations.business_id (e.g.
      // once-off / bill deals that have no discount row).
      businessName:
          (json['trusted_partner_discounts']?['businesses']?['name']
              as String?) ??
          (json['businesses']?['name'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'member_id': memberId,
      'trusted_partner_id': trustedPartnerId,
      'business_id': businessId,
      'discount_id': discountId,
      'status': status,
      'authorization_type': authorizationType,
      'payment_method': paymentMethod,
      'amount': amount,
      'member_entered_price': memberEnteredPrice,
      'applied_discount_amount': appliedDiscountAmount,
      'deal_type': dealType,
      'deal_snapshot': dealSnapshot,
      'notes': notes,
      'rejection_reason': rejectionReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'approved_at': approvedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }
}
