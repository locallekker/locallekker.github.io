import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/models/member_receipt.dart';

void main() {
  test('receipt book parses and serializes the deployed member_receipts schema', () {
    final receipt = MemberReceipt.fromJson({
      'id': 'receipt', 'member_id': 'member', 'virtual_receipt_id': 'virtual',
      'title': 'RCP-fixture', 'receipt_type': 'virtual', 'business_name': 'Fixture',
      'amount': 90, 'receipt_date': '2026-11-12T12:00:00Z', 'created_at': '2026-11-12T12:01:00Z',
    });
    expect(receipt.receiptNumber, 'RCP-fixture');
    expect(receipt.amount, 90);
    expect(receipt.savedAt, DateTime.utc(2026, 11, 12, 12, 1));
    final encoded = receipt.toJson();
    expect(encoded['receipt_type'], 'virtual');
    expect(encoded['title'], 'RCP-fixture');
    expect(encoded.containsKey('transaction_date'), isFalse);
    expect(MemberReceipt.fromJson(encoded).transactionDate, receipt.transactionDate);
  });
}
