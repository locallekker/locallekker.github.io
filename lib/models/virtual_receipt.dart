import 'deal_authorization.dart';

class VirtualReceipt {
  final String id;
  final String dealAuthorizationId;
  final String receiptNumber;
  final Map<String, dynamic> receiptData;
  final String? qrCode;
  final DateTime createdAt;

  // Related data
  final DealAuthorization? dealAuthorization;

  VirtualReceipt({
    required this.id,
    required this.dealAuthorizationId,
    required this.receiptNumber,
    required this.receiptData,
    this.qrCode,
    required this.createdAt,
    this.dealAuthorization,
  });

  factory VirtualReceipt.fromJson(Map<String, dynamic> json) {
    return VirtualReceipt(
      id: json['id'],
      dealAuthorizationId: json['deal_authorization_id'],
      receiptNumber: json['receipt_number'],
      receiptData: json['receipt_data'],
      qrCode: json['qr_code'],
      createdAt: DateTime.parse(json['created_at']),
      dealAuthorization: json['deal_authorization'] != null
          ? DealAuthorization.fromJson(json['deal_authorization'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deal_authorization_id': dealAuthorizationId,
      'receipt_number': receiptNumber,
      'receipt_data': receiptData,
      'qr_code': qrCode,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
