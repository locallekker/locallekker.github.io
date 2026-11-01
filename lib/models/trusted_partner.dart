class TrustedPartner {
  final String? id;
  final String? businessId;
  final String? ownerMemberId;
  final String? paystackSubaccountId;
  final String? businessName;
  final String? businessType;
  final String? contactEmail;
  final String? contactPhone;
  final String? address;
  final String? city;
  final String? province;
  final String? postalCode;
  final String? taxNumber;
  final String? bankAccountHolder;
  final String? bankName;
  final String? bankAccountNumber;
  final String? bankBranchCode;
  final String? bankAccountType;
  final double? settlementPercentage;
  final bool? isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TrustedPartner({
    this.id,
    this.businessId,
    this.ownerMemberId,
    this.paystackSubaccountId,
    this.businessName,
    this.businessType,
    this.contactEmail,
    this.contactPhone,
    this.address,
    this.city,
    this.province,
    this.postalCode,
    this.taxNumber,
    this.bankAccountHolder,
    this.bankName,
    this.bankAccountNumber,
    this.bankBranchCode,
    this.bankAccountType,
    this.settlementPercentage,
    this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  factory TrustedPartner.fromJson(Map<String, dynamic> json) {
    return TrustedPartner(
      id: json['id'],
      businessId: json['business_id'],
      ownerMemberId: json['owner_member_id'],
      paystackSubaccountId: json['paystack_subaccount_id'],
      businessName: json['business_name'],
      businessType: json['business_type'],
      contactEmail: json['contact_email'],
      contactPhone: json['contact_phone'],
      address: json['address'],
      city: json['city'],
      province: json['province'],
      postalCode: json['postal_code'],
      taxNumber: json['tax_number'],
      bankAccountHolder: json['bank_account_holder'],
      bankName: json['bank_name'],
      bankAccountNumber: json['bank_account_number'],
      bankBranchCode: json['bank_branch_code'],
      bankAccountType: json['bank_account_type'],
      settlementPercentage: json['settlement_percentage'] != null
          ? (json['settlement_percentage'] as num).toDouble()
          : null,
      isActive: json['is_active'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (ownerMemberId != null) 'owner_member_id': ownerMemberId,
      if (paystackSubaccountId != null)
        'paystack_subaccount_id': paystackSubaccountId,
      if (businessName != null) 'business_name': businessName,
      if (businessType != null) 'business_type': businessType,
      if (contactEmail != null) 'contact_email': contactEmail,
      if (contactPhone != null) 'contact_phone': contactPhone,
      if (address != null) 'address': address,
      if (city != null) 'city': city,
      if (province != null) 'province': province,
      if (postalCode != null) 'postal_code': postalCode,
      if (taxNumber != null) 'tax_number': taxNumber,
      if (bankAccountHolder != null) 'bank_account_holder': bankAccountHolder,
      if (bankName != null) 'bank_name': bankName,
      if (bankAccountNumber != null) 'bank_account_number': bankAccountNumber,
      if (bankBranchCode != null) 'bank_branch_code': bankBranchCode,
      if (bankAccountType != null) 'bank_account_type': bankAccountType,
      if (settlementPercentage != null)
        'settlement_percentage': settlementPercentage,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}
