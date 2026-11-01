import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/models/discount.dart';
import 'package:local_lekker/models/restaurant_deal.dart';
import 'package:local_lekker/services/partner_qr_redemption_service.dart';

Discount discount({
  String type = 'standard',
  double itemPrice = 95,
  double percentage = 0,
  double? fixedAmount,
  bool isWeightBased = false,
  bool isBillDiscount = false,
  bool isOnceOff = false,
  bool requiresManualPrice = false,
  Map<String, dynamic>? customData,
  Map<String, dynamic>? billDiscountData,
}) =>
    Discount(
      id: 'deal-id',
      trustedPartnerId: 'partner-id',
      name: 'Test deal',
      description: '',
      itemName: 'Breakfast',
      itemPrice: itemPrice,
      percentage: percentage,
      fixedAmount: fixedAmount,
      dealType: type,
      customData: customData,
      requiresManualPrice: requiresManualPrice,
      isActive: true,
      isWeightBased: isWeightBased,
      isBillDiscount: isBillDiscount,
      isOnceOff: isOnceOff,
      billDiscountData: billDiscountData,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  group('Partner QR redemption calculator', () {
    test('calculates a fixed-price deal for multiple items', () {
      final quote = PartnerQrRedemptionService.quote(
        deal: discount(fixedAmount: 16),
        billTotal: 190,
        quantity: 2,
      );

      expect(quote.isValid, isTrue);
      expect(quote.discount, 32);
      expect(quote.total, 158);
    });

    test('calculates a bill percentage after excluding items', () {
      final quote = PartnerQrRedemptionService.quote(
        deal: discount(
          isBillDiscount: true,
          percentage: 20,
          billDiscountData: {'isPercentage': true},
        ),
        billTotal: 500,
        excludedAmount: 100,
        extrasAmount: 30,
      );

      expect(quote.discount, 80);
      expect(quote.total, 420);
    });

    test('uses the entered price only for manual percentage deals', () {
      final quote = PartnerQrRedemptionService.quote(
        deal: discount(
          type: 'percent_item',
          percentage: 20,
          requiresManualPrice: true,
        ),
        billTotal: 100,
        quantity: 2,
        manualUnitPrice: 50,
      );

      expect(quote.discount, 20);
      expect(quote.total, 80);
    });

    test('calculates weight-based savings in grams', () {
      final quote = PartnerQrRedemptionService.quote(
        deal: discount(
          itemPrice: 200,
          percentage: 10,
          isWeightBased: true,
        ),
        billTotal: 100,
        quantity: 500,
      );

      expect(quote.discount, 10);
      expect(quote.total, 90);
    });

    test('calculates restaurant deal totals using restaurant rules', () {
      final quote = PartnerQrRedemptionService.quote(
        deal: discount(
          type: RestaurantDealType.foodPercent.key,
          percentage: 20,
          customData: {'percentage': 20},
        ),
        billTotal: 500,
        tip: 50,
        restaurantInputs: const RestaurantDealInputs(
          billTotal: 500,
          tip: 50,
          excludedAmount: 100,
        ),
      );

      expect(quote.discount, 80);
      expect(quote.total, 470);
    });

    test('rejects quantities outside the supported range', () {
      final quote = PartnerQrRedemptionService.quote(
        deal: discount(),
        billTotal: 100,
        quantity: 201,
      );

      expect(quote.isValid, isFalse);
    });

    test('checkout-priced cocktails carry server-recalculable prices', () {
      final quote = PartnerQrRedemptionService.quote(
        deal: discount(
          type: RestaurantDealType.bogo.key,
          customData: {
            'item_name': 'cocktails',
            'pricing_mode': 'checkout',
            'buy_qty': 1,
            'free_qty': 1,
          },
        ),
        billTotal: 170,
        restaurantInputs: const RestaurantDealInputs(
          billTotal: 170, itemQty: 2, itemPrices: [95, 75],
        ),
      );
      expect(quote.isValid, isTrue);
      expect(quote.discount, 75);
      expect(quote.total, 95);
      expect(quote.checkoutData['restaurant']['inputs']['item_prices'], [95, 75]);
    });

    test('does not redeem a deal when it gives no savings', () {
      final quote = PartnerQrRedemptionService.quote(
        deal: discount(),
        billTotal: 100,
        quantity: 1,
      );

      expect(quote.isValid, isFalse);
    });
  });
}
