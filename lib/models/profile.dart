class Profile {
  final String id;
  final String? name;
  final String? surname;
  final String? email;
  final String? category;
  final String? city;
  final String? contact;
  final String? province;
  final String? street;
  final String? suburb;
  final String? gender;
  final String? ethnicity;
  final String? dateOfBirth;
  final String? role;
  final bool? verified; // Admin verification status
  final bool? isTpMember; // Trusted partner member flag
  final bool? partnerTermsAccepted; // Trusted partner T&C acceptance
  final DateTime? createdAt;
  final DateTime? updatedAt;
  // Paystack integration fields
  final String? paystackCustomerCode;
  final String? paystackAuthCode;

  Profile({
    required this.id,
    this.name,
    this.surname,
    this.email,
    this.category,
    this.city,
    this.contact,
    this.province,
    this.street,
    this.suburb,
    this.gender,
    this.ethnicity,
    this.dateOfBirth,
    this.role,
    this.verified,
    this.isTpMember,
    this.partnerTermsAccepted,
    this.createdAt,
    this.updatedAt,
    // Paystack integration fields
    this.paystackCustomerCode,
    this.paystackAuthCode,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'],
      name: json['name'],
      surname: json['surname'],
      email: json['email'],
      category: json['category'],
      city: json['city'],
      contact: json['contact'],
      province: json['province'],
      street: json['street'],
      suburb: json['suburb'],
      gender: json['gender'],
      ethnicity: json['ethnicity'],
      dateOfBirth: json['date_of_birth'],
      role: json['role'],
      verified: json['verified'],
      isTpMember: json['is_tp_member'],
      partnerTermsAccepted: json['partner_terms_accepted'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      // Paystack integration fields
      paystackCustomerCode: json['paystack_customer_code'],
      paystackAuthCode: json['paystack_auth_code'],
    );
  }
}
