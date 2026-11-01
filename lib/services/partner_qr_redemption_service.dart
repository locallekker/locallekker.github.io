import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/discount.dart';
import '../models/restaurant_deal.dart';
import 'supabase_service.dart';

class PartnerQrDealQuote {
  final double billTotal;
  final double discount;
  final double tip;
  final double total;
  final String summary;
  final String? error;
  final Map<String, dynamic> checkoutData;

  const PartnerQrDealQuote({
    required this.billTotal,
    required this.discount,
    required this.tip,
    required this.total,
    required this.summary,
    required this.checkoutData,
    this.error,
  });

  bool get isValid => error == null;
}

class PartnerQrRedemptionService {
  PartnerQrRedemptionService({SupabaseClient? client})
      : _client = client ?? SupabaseService.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> verifyMemberQr({
    required String businessId,
    required String qrPayload,
  }) async {
    final result = await _client.rpc(
      'verify_member_qr_for_partner',
      params: {
        'p_business_id': businessId,
        'p_qr_payload': qrPayload,
      },
    );
    if (result is! Map) {
      throw const FormatException('Member verification returned an invalid result.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<List<Discount>> getActiveDeals(String businessId) async {
    final rows = await _client
        .from('trusted_partner_discounts')
        .select()
        .eq('business_id', businessId)
        .eq('is_active', true)
        .order('name');

    return rows
        .whereType<Map<String, dynamic>>()
        .map(Discount.fromJson)
        .where(
          (deal) =>
              !deal.isWebsiteRedirect &&
              !deal.isBookingRedirect &&
              !deal.isFreeDelivery &&
              (!deal.isRestaurantDeal || deal.restaurantConfig != null),
        )
        .toList();
  }

  Future<String> completeRedemption({
    required String businessId,
    required String redemptionSessionId,
    required Discount deal,
    required PartnerQrDealQuote quote,
    required double posTotal,
    required String idempotencyKey,
    required double extrasAmount,
    required String checkoutNotes,
  }) async {
    final checkoutData = Map<String, dynamic>.from(quote.checkoutData);
    final checkoutDetails = <String, dynamic>{
      if (checkoutData['checkout'] is Map)
        ...Map<String, dynamic>.from(checkoutData['checkout'] as Map),
      'extras_amount': _roundMoney(extrasAmount),
      if (checkoutNotes.trim().isNotEmpty)
        'adjustments_note': checkoutNotes.trim(),
    };
    final result = await _client.rpc(
      'redeem_deal_via_redemption_session',
      params: {
        'p_business_id': businessId,
        'p_redemption_session_id': redemptionSessionId,
        'p_discount_id': deal.id,
        'p_checkout': {
          ...checkoutData,
          'checkout': checkoutDetails,
          'redemption_session_id': redemptionSessionId,
        },
        'p_pos_total': _roundMoney(posTotal),
        'p_idempotency_key': idempotencyKey,
      },
    );
    if (result is! String || result.isEmpty) {
      throw const FormatException('The redemption could not be confirmed.');
    }
    return result;
  }

  static PartnerQrDealQuote quote({
    required Discount deal,
    required double billTotal,
    double tip = 0,
    int quantity = 1,
    double? manualUnitPrice,
    double excludedAmount = 0,
    double extrasAmount = 0,
    RestaurantDealInputs? restaurantInputs,
  }) {
    final bill = _roundMoney(billTotal);
    final safeTip = _roundMoney(tip);
    final baseData = <String, dynamic>{
      'original_bill_amount': bill,
      'tip_amount': safeTip,
    };
    PartnerQrDealQuote failure(String message) => PartnerQrDealQuote(
          billTotal: bill,
          discount: 0,
          tip: safeTip,
          total: bill + safeTip,
          summary: '',
          error: message,
          checkoutData: baseData,
        );

    if (bill <= 0 || bill > 100000) {
      return failure('Enter a bill total between R0.01 and R100,000.');
    }
    if (safeTip < 0 || safeTip > bill) {
      return failure('Tip cannot be more than the bill.');
    }
    if (extrasAmount < 0 || _roundMoney(extrasAmount) > bill) {
      return failure('Extras cannot be more than the original bill.');
    }

    final restaurant = deal.restaurantConfig;
    if (restaurant != null) {
      if (restaurantInputs == null) {
        return failure('Enter the details required for this restaurant deal.');
      }
      final restaurantQuote = restaurant.quote(restaurantInputs);
      if (!restaurantQuote.isValid) {
        return failure(restaurantQuote.error ?? 'Check the deal details.');
      }
      if (restaurantQuote.discount <= 0) {
        return failure('This bill does not qualify for a discount from this deal.');
      }
      return PartnerQrDealQuote(
        billTotal: restaurantQuote.billTotal,
        discount: restaurantQuote.discount,
        tip: restaurantQuote.tip,
        total: restaurantQuote.total,
        summary: restaurantQuote.summary,
        checkoutData: buildRestaurantBillData(
          type: restaurant.type,
          inputs: restaurantInputs,
          quote: restaurantQuote,
        ),
      );
    }

    if (deal.isBillDiscount) {
      final excluded = _roundMoney(excludedAmount);
      if (excluded < 0 || excluded > bill) {
        return failure('Excluded items cannot exceed the bill.');
      }
      final eligible = bill - excluded;
      final percent = deal.billDiscountData?['isPercentage'] == true;
      final discount = percent
          ? eligible * deal.percentage.clamp(0, 100) / 100
          : (deal.fixedAmount ?? 0).clamp(0, eligible);
      final roundedDiscount = _roundMoney(discount);
      if (roundedDiscount <= 0) {
        return failure('This bill does not qualify for a discount from this deal.');
      }
      return PartnerQrDealQuote(
        billTotal: bill,
        discount: roundedDiscount,
        tip: safeTip,
        total: _roundMoney(bill - roundedDiscount + safeTip),
        summary: percent
            ? '${deal.percentage.toStringAsFixed(0)}% off eligible bill items'
            : 'R${roundedDiscount.toStringAsFixed(2)} off the bill',
        checkoutData: {
          ...baseData,
          'checkout': {'excluded_amount': excluded},
        },
      );
    }

    final maxQuantity = deal.isWeightBased ? 200000 : 200;
    if (quantity < 1 || quantity > maxQuantity) {
      return failure('Check the quantity or weight.');
    }
    if (deal.isOnceOff && quantity != 1) {
      return failure('This one-time deal can only be redeemed once.');
    }

    final isManualPercent = deal.isPercentItem && deal.requiresManualPrice;
    final unitPrice = isManualPercent ? (manualUnitPrice ?? 0) : deal.itemPrice;
    if (unitPrice <= 0 || unitPrice > 100000) {
      return failure('This deal needs a valid item price.');
    }

    double discount;
    if (deal.isBuyGet) {
      final comboPrice =
          (deal.customData?['total_price'] as num?)?.toDouble() ??
              deal.dealPrice;
      final regularPrice =
          (deal.customData?['buy_item_price'] as num?)?.toDouble() ??
              unitPrice;
      discount = math.max(0.0, regularPrice - comboPrice) * quantity;
    } else {
      final double unitDiscount = isManualPercent
          ? unitPrice * deal.percentage.clamp(0, 100).toDouble() / 100
          : deal.fixedAmount != null && deal.fixedAmount! > 0
              ? math.min(deal.fixedAmount!, unitPrice).toDouble()
              : unitPrice * deal.percentage.clamp(0, 100).toDouble() / 100;
      discount = unitDiscount *
          (deal.isWeightBased ? quantity / 1000 : quantity);
    }

    final roundedDiscount = _roundMoney(math.min(discount, bill));
    if (roundedDiscount <= 0) {
      return failure('This bill does not qualify for a discount from this deal.');
    }
    final checkoutData = <String, dynamic>{
      ...baseData,
      'checkout': {
        'quantity': quantity,
        if (isManualPercent) 'unit_price': _roundMoney(unitPrice),
      },
    };
    return PartnerQrDealQuote(
      billTotal: bill,
      discount: roundedDiscount,
      tip: safeTip,
      total: _roundMoney(bill - roundedDiscount + safeTip),
      summary: '$quantity × ${deal.itemName}',
      checkoutData: checkoutData,
    );
  }

  static double _roundMoney(num value) => (value * 100).roundToDouble() / 100;
}
