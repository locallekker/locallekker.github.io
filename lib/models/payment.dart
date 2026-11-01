class PaymentModel {
  final String? id;
  final String? userId;
  final String? planName;
  final double? amount;
  final String? paymentMethod;
  final String? transactionId;
  final String? status;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  // Paystack integration fields
  final String? paystackReference;
  final Map<String, dynamic>? rawEvent;

  PaymentModel({
    this.id,
    this.userId,
    this.planName,
    this.amount,
    this.paymentMethod,
    this.transactionId,
    this.status,
    this.completedAt,
    this.createdAt,
    this.updatedAt,
    // Paystack integration fields
    this.paystackReference,
    this.rawEvent,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      id: json['id'],
      userId: json['user_id'],
      planName: json['plan_name'],
      amount: json['amount'] != null
          ? (json['amount'] as num).toDouble()
          : null,
      paymentMethod: json['payment_method'],
      transactionId: json['transaction_id'],
      status: json['status'],
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      // Paystack integration fields
      paystackReference: json['paystack_reference'],
      rawEvent: json['raw_event'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (planName != null) 'plan_name': planName,
      if (amount != null) 'amount': amount,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (transactionId != null) 'transaction_id': transactionId,
      if (status != null) 'status': status,
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      // Paystack integration fields
      if (paystackReference != null) 'paystack_reference': paystackReference,
      if (rawEvent != null) 'raw_event': rawEvent,
    };
  }
}
