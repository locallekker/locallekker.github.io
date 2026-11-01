import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/services/payment_status_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PaymentStatusService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = PaymentStatusService();
  });

  group('pending plan', () {
    test('round-trips plan details for the same member', () async {
      await service.savePendingPayment(
        memberId: 'u1',
        selectedPlan: 'monthly',
        planDetails: {'price': 99, 'name': 'Monthly'},
      );

      expect(await service.hasPendingPayment('u1'), isTrue);
      expect(await service.getPendingPayment('u1'), {
        'selectedPlan': 'monthly',
        'planDetails': {'price': 99, 'name': 'Monthly'},
      });
    });

    test('is invisible to, and not cleared by, another member', () async {
      await service.savePendingPayment(
        memberId: 'u1',
        selectedPlan: 'monthly',
        planDetails: {'price': 99},
      );

      expect(await service.getPendingPayment('u2'), isNull);
      await service.clearPendingPayment('u2');
      expect(await service.hasPendingPayment('u1'), isTrue);

      await service.clearPendingPayment('u1');
      expect(await service.hasPendingPayment('u1'), isFalse);
    });

    test('corrupted details are discarded instead of crashing', () async {
      SharedPreferences.setMockInitialValues({
        'pending_payment_member_id': 'u1',
        'pending_payment_plan': 'monthly',
        'pending_payment_plan_details': '{not json',
      });

      expect(await service.getPendingPayment('u1'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pending_payment_member_id'), isNull);
    });
  });

  group('pending transaction reference', () {
    test('is scoped to the user that started the checkout', () async {
      await service.savePendingTransactionReference(
        userId: 'u1',
        reference: 'ref_123',
        planType: 'monthly',
      );

      expect(await service.getPendingTransactionReference('u1'), {
        'reference': 'ref_123',
        'planType': 'monthly',
      });
      expect(await service.getPendingTransactionReference('u2'), isNull);

      await service.clearPendingTransactionReference('u2');
      expect(await service.getPendingTransactionReference('u1'), isNotNull);

      await service.clearPendingTransactionReference('u1');
      expect(await service.getPendingTransactionReference('u1'), isNull);
    });
  });
}
