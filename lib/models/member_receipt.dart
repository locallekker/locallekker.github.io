class MemberReceipt {
  final String id;
  final String memberId;
  final String virtualReceiptId;
  final String receiptNumber;
  final String businessName;
  final double amount;
  final DateTime transactionDate;
  final String status; // saved, used, expired
  final DateTime savedAt;

  MemberReceipt({
    required this.id,
    required this.memberId,
    required this.virtualReceiptId,
    required this.receiptNumber,
    required this.businessName,
    required this.amount,
    required this.transactionDate,
    required this.status,
    required this.savedAt,
  });

  factory MemberReceipt.fromJson(Map<String, dynamic> json) {
    return MemberReceipt(
      id: json['id'],
      memberId: json['member_id'],
      virtualReceiptId: json['virtual_receipt_id'],
      receiptNumber: json['receipt_number'],
      businessName: json['business_name'],
      amount: (json['amount'] as num).toDouble(),
      transactionDate: DateTime.parse(json['transaction_date']),
      status: json['status'],
      savedAt: DateTime.parse(json['saved_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'member_id': memberId,
      'virtual_receipt_id': virtualReceiptId,
      'receipt_number': receiptNumber,
      'business_name': businessName,
      'amount': amount,
      'transaction_date': transactionDate.toIso8601String(),
      'status': status,
      'saved_at': savedAt.toIso8601String(),
    };
  }
}
