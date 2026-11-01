import 'dart:io';
import 'package:logger/logger.dart';
import 'supabase_service.dart';

/// Service for fetching member savings statistics
class SavingsService {
  static final SavingsService _instance = SavingsService._internal();
  factory SavingsService() => _instance;
  SavingsService._internal();

  final Logger _logger = Logger();

  /// Get total savings statistics for a member based on deal receipts
  /// Returns:
  /// - totalDeals: Number of completed deal receipts
  /// - totalSaved: Total discount amount from deals
  /// - totalSpent: Total original amount before discount (excluding tips)
  /// - totalPaid: Total amount paid after discount (including tips)
  /// - totalTips: Total tips paid
  /// - mostUsedPartner: Partner ID with most transactions
  Future<Map<String, dynamic>?> getUserSavingsStats(String userId) async {
    try {
      _logger.i('🔍 Fetching savings statistics for user: $userId');

      // Fetch all deal receipts with authorization and discount details
      final response = await SupabaseService.instance.client
          .from('deal_receipts')
          .select('''
            id,
            amount,
            business_id,
            deal_authorization_id,
            deal_authorizations!inner (
              amount,
              payment_method,
              quantity,
              discount_id,
              bill_data,
              trusted_partner_discounts (
                is_weight_based,
                is_bill_discount,
                bill_discount_data,
                percentage,
                fixed_amount,
                item_price
              )
            )
          ''')
          .eq('member_id', userId);

      _logger.i('📊 Deal receipts response: ${response.length} receipts found');
      if (response.isNotEmpty) {
        _logger.d('📄 First receipt sample: ${response.first}');
      }

      // Calculate totals from deal receipts
      double totalSaved = 0;
      double totalSpent = 0;
      double totalTips = 0;
      double totalPaid =
          0; // Sum of what user actually paid (final_amount for bills)
        double totalInAppPayments = 0;
        double totalPosPayments = 0;
      int totalDeals = response.length;
      Map<String, int> partnerCounts = {};

      for (var receipt in response) {
        _logger.d('Processing receipt: ${receipt['id']}');

        final authorization = receipt['deal_authorizations'];
        if (authorization != null) {
          final dealAmount = authorization['amount'] != null
              ? (authorization['amount'] as num).toDouble()
              : 0.0;
          final paymentMethod = authorization['payment_method']?.toString();
          double methodPaymentAmount = 0.0;
          bool hasMethodPaymentAmount = false;

          _logger.d('  Deal amount: $dealAmount');

          final discount = authorization['trusted_partner_discounts'];

          if (discount != null && dealAmount > 0) {
            // Check if this is a bill discount deal
            final isBillDiscount = discount['is_bill_discount'] == true;

            if (isBillDiscount) {
              // For bill discounts, use stored bill_data for accurate calculations
              final billData =
                  authorization['bill_data'] as Map<String, dynamic>?;

              if (billData != null) {
                final originalBillAmount =
                    billData['original_bill_amount'] != null
                    ? (billData['original_bill_amount'] as num).toDouble()
                    : 0.0;
                final discountAmount = billData['discount_amount'] != null
                    ? (billData['discount_amount'] as num).toDouble()
                    : 0.0;
                final tipAmount = billData['tip_amount'] != null
                    ? (billData['tip_amount'] as num).toDouble()
                    : 0.0;
                final finalAmount = billData['final_amount'] != null
                    ? (billData['final_amount'] as num).toDouble()
                    : 0.0;

                if (originalBillAmount > 0 && finalAmount > 0) {
                  totalSaved += discountAmount; // may be 0 if no discount
                  totalSpent += originalBillAmount;
                  totalTips += tipAmount;
                  totalPaid += finalAmount; // Use final_amount for paid
                  methodPaymentAmount = finalAmount;
                  hasMethodPaymentAmount = true;

                  _logger.d(
                    '  Bill discount (from bill_data): Original: R$originalBillAmount, Discount: R$discountAmount, Tip: R$tipAmount, Paid: R$finalAmount',
                  );
                } else {
                  _logger.w('  ⚠️ Bill data missing or invalid (originalBillAmount=$originalBillAmount, finalAmount=$finalAmount)');
                }
              } else {
                // Fallback: try to parse from notes or estimate
                _logger.w(
                  '  ⚠️ No bill_data found, using fallback calculation',
                );
                final billDiscountData =
                    discount['bill_discount_data'] as Map<String, dynamic>?;
                if (billDiscountData != null) {
                  final isPercentage = billDiscountData['isPercentage'] == true;
                  final percentage = discount['percentage'] != null
                      ? (discount['percentage'] as num).toDouble()
                      : 0.0;
                  final fixedAmount = discount['fixed_amount'] != null
                      ? (discount['fixed_amount'] as num).toDouble()
                      : 0.0;

                  double saved = 0.0;
                  if (isPercentage && percentage > 0) {
                    final discountFactor = 1 - (percentage / 100);
                    final originalAmount = dealAmount / discountFactor;
                    saved = originalAmount - dealAmount;
                    totalSpent += originalAmount;
                  } else if (fixedAmount > 0) {
                    saved = fixedAmount;
                    totalSpent += dealAmount + fixedAmount;
                  }

                  totalSaved += saved;
                  totalPaid += dealAmount; // Track payment even in fallback path
                  methodPaymentAmount = dealAmount;
                  hasMethodPaymentAmount = true;
                  _logger.d(
                    '  Bill discount (fallback): Amount paid: R$dealAmount, Saved: R$saved',
                  );
                }
              }
            } else {
              // Item-based deal calculation
              final itemPrice = discount['item_price'] != null
                  ? (discount['item_price'] as num).toDouble()
                  : 0.0;
              final fixedAmount = discount['fixed_amount'] != null
                  ? (discount['fixed_amount'] as num).toDouble()
                  : 0.0;
              final percentage = discount['percentage'] != null
                  ? (discount['percentage'] as num).toDouble()
                  : 0.0;

              final isWeightBased = discount['is_weight_based'] == true;

              _logger.d(
                '  Item discount - Price: $itemPrice, Fixed: $fixedAmount, Percentage: $percentage, Weight-based: $isWeightBased',
              );

              if (isWeightBased) {
                // Weight-based: quantity field contains grams purchased
                // For new deals, use stored quantity. For legacy deals without quantity, reverse-calculate from amount paid
                final storedQuantity = authorization['quantity'] as int?;
                double quantity;

                if (storedQuantity != null && storedQuantity > 0) {
                  // New deal with stored quantity
                  quantity = storedQuantity.toDouble();
                } else {
                  // Legacy deal without quantity - reverse calculate from amount paid
                  // Calculate deal price per kg
                  double dealPricePerKg;
                  if (fixedAmount > 0) {
                    dealPricePerKg = itemPrice - fixedAmount;
                  } else if (percentage > 0) {
                    dealPricePerKg = itemPrice * (1 - percentage / 100);
                  } else {
                    dealPricePerKg = itemPrice; // No discount
                  }

                  // Reverse calculate: quantity_kg = amount_paid / deal_price_per_kg
                  quantity = dealPricePerKg > 0
                      ? dealAmount / dealPricePerKg * 1000
                      : 0.0;
                }

                final kg = quantity / 1000.0;
                double originalCost = itemPrice * kg;

                double saved = 0.0;
                if (itemPrice > 0) {
                  if (fixedAmount > 0) {
                    saved = fixedAmount * kg;
                  } else if (percentage > 0) {
                    saved = originalCost * (percentage / 100);
                  }
                } else {
                  // item_price missing: reverse-calculate from discount type if possible
                  if (percentage > 0 && dealAmount > 0) {
                    originalCost = dealAmount / (1.0 - percentage / 100.0);
                    saved = originalCost - dealAmount;
                    _logger.w(
                      '  ⚠️ Weight: item_price=0, reverse-calculated from percentage: Original=R${originalCost.toStringAsFixed(2)}, Saved=R${saved.toStringAsFixed(2)}',
                    );
                  } else {
                    // Can't calculate; use paid amount as a floor for originalCost
                    originalCost = dealAmount;
                    saved = 0.0;
                    _logger.w(
                      '  ⚠️ Weight: item_price=0 and no percentage, using dealAmount as originalCost',
                    );
                  }
                }

                totalSpent += originalCost;
                totalSaved += saved;
                totalPaid +=
                    dealAmount; // Add the actual amount paid for weight deal
                methodPaymentAmount = dealAmount;
                hasMethodPaymentAmount = true;
                _logger.d(
                  '  Weight calc: ${quantity.toStringAsFixed(0)}g = ${kg.toStringAsFixed(3)}kg, Original: R${originalCost.toStringAsFixed(2)}, Saved: R${saved.toStringAsFixed(2)}',
                );
              } else {
                // Regular item-based: dealAmount is the FINAL DISCOUNTED PRICE, not quantity!
                // We need to reverse-calculate the quantity from the stored amount

                double originalCost;
                double saved = 0.0;

                if (itemPrice > 0) {
                  // Normal path: calculate using item_price
                  double dealPrice;
                  if (fixedAmount > 0) {
                    dealPrice = itemPrice - fixedAmount;
                  } else if (percentage > 0) {
                    dealPrice = itemPrice * (1 - percentage / 100);
                  } else {
                    dealPrice = itemPrice;
                  }

                  // Reverse-calculate quantity: quantity = finalAmount / dealPrice
                  final quantity = dealPrice > 0 ? dealAmount / dealPrice : 0.0;
                  originalCost = itemPrice * quantity;

                  if (fixedAmount > 0) {
                    saved = fixedAmount * quantity;
                  } else if (percentage > 0) {
                    saved = originalCost * (percentage / 100);
                  }
                  _logger.d(
                    '  Item calc: Paid R$dealAmount for ${quantity.toStringAsFixed(2)}x @ R$itemPrice, Original: R${originalCost.toStringAsFixed(2)}, Saved: R${saved.toStringAsFixed(2)}',
                  );
                } else if (percentage > 0 && dealAmount > 0) {
                  // item_price missing: reverse-calculate original cost from the percentage
                  originalCost = dealAmount / (1.0 - percentage / 100.0);
                  saved = originalCost - dealAmount;
                  _logger.w(
                    '  ⚠️ Item: item_price=0, reverse-calculated from percentage: Original=R${originalCost.toStringAsFixed(2)}, Saved=R${saved.toStringAsFixed(2)}',
                  );
                } else if (fixedAmount > 0 && dealAmount > 0) {
                  // item_price missing but fixed discount known: assume 1 unit
                  originalCost = dealAmount + fixedAmount;
                  saved = fixedAmount;
                  _logger.w(
                    '  ⚠️ Item: item_price=0, estimated 1 unit from fixedAmount: Original=R${originalCost.toStringAsFixed(2)}, Saved=R${saved.toStringAsFixed(2)}',
                  );
                } else {
                  // Cannot determine original cost; use paid amount as a floor
                  originalCost = dealAmount;
                  saved = 0.0;
                  _logger.w(
                    '  ⚠️ Item: item_price=0 with no discount params, using dealAmount as originalCost',
                  );
                }

                totalSpent += originalCost;
                totalSaved += saved;
                totalPaid +=
                    dealAmount; // Add the actual amount paid for item deal
                methodPaymentAmount = dealAmount;
                hasMethodPaymentAmount = true;
              }
            }

            if (hasMethodPaymentAmount) {
              if (paymentMethod == 'in_app') {
                totalInAppPayments += methodPaymentAmount;
              } else if (paymentMethod == 'pos') {
                totalPosPayments += methodPaymentAmount;
              }
            }
          } else {
            _logger.w('  ⚠️ Missing discount data or zero amount');
          }
        } else {
          _logger.w('  ⚠️ No authorization data for receipt');
        }

        // Track partner usage
        final businessId = receipt['business_id'] as String?;
        if (businessId != null) {
          partnerCounts[businessId] = (partnerCounts[businessId] ?? 0) + 1;
        }
      }

      // Find most used partner
      String? mostUsedPartner;
      int maxCount = 0;
      partnerCounts.forEach((partnerId, count) {
        if (count > maxCount) {
          maxCount = count;
          mostUsedPartner = partnerId;
        }
      });

      final stats = {
        'totalDeals': totalDeals,
        'totalSaved': totalSaved,
        'totalSpent': totalSpent,
        'totalPaid': totalPaid,
        'totalTips': totalTips,
        'totalInAppPayments': totalInAppPayments,
        'totalPosPayments': totalPosPayments,
        'mostUsedPartner': mostUsedPartner,
      };

      _logger.i(
        '💰 Final savings stats: Deals=$totalDeals, Spent=R${totalSpent.toStringAsFixed(2)}, Saved=R${totalSaved.toStringAsFixed(2)}, Tips=R${totalTips.toStringAsFixed(2)}, Paid=R${totalPaid.toStringAsFixed(2)}, InApp=R${totalInAppPayments.toStringAsFixed(2)}, POS=R${totalPosPayments.toStringAsFixed(2)}',
      );
      return stats;
    } catch (e, stackTrace) {
      final errorMsg =
          'Error fetching savings statistics for user $userId: '
          '${e.runtimeType} - ${e.toString()}';
      _logger.e('❌ $errorMsg');
      _logger.e('Stack trace: $stackTrace');

      // Write a compact debug record to a temp log file so developers can
      // retrieve detailed failure info from a device/emulator.
      try {
        final file = File(
          '${Directory.systemTemp.path}/local_lekker_receipt_errors.log',
        );
        final now = DateTime.now().toIso8601String();
        final entry = StringBuffer()
          ..writeln('----')
          ..writeln('timestamp: $now')
          ..writeln('context: getUserSavingsStats')
          ..writeln('userId: $userId')
          ..writeln('error: $errorMsg')
          ..writeln('stack: $stackTrace')
          ..writeln();

        file.writeAsStringSync(
          entry.toString(),
          mode: FileMode.append,
          flush: true,
        );
      } catch (fileErr) {
        _logger.w('Could not write local debug log: $fileErr');
      }

      return null;
    }
  }

  /// Get detailed list of deal authorizations for a member
  Future<List<Map<String, dynamic>>> getUserDealAuthorizations(
    String userId, {
    int limit = 10,
    int offset = 0,
  }) async {
    try {
      _logger.i('Fetching deal authorizations for user: $userId');

      final response = await SupabaseService.instance.client
          .from('deal_authorizations')
          .select('''
            id,
            amount,
            status,
            trusted_partner_id,
            discount_id,
            created_at,
            approved_at,
            completed_at,
            trusted_partner_discounts (
              product_name,
              savings,
              regular_price,
              discounted_price,
              is_weight_based
            ),
            businesses!deal_authorizations_trusted_partner_id_fkey (
              business_name
            )
          ''')
          .eq('member_id', userId)
          .inFilter('status', ['approved', 'completed'])
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      _logger.d('Deal authorizations response: ${response.length} deals found');
      return List<Map<String, dynamic>>.from(response);
    } catch (e, stackTrace) {
      _logger.e('Error fetching deal authorizations for $userId: $e');
      try {
        final file = File(
          '${Directory.systemTemp.path}/local_lekker_receipt_errors.log',
        );
        final now = DateTime.now().toIso8601String();
        file.writeAsStringSync(
          '\n----\ntimestamp: $now\ncontext: getUserDealAuthorizations\nuserId: $userId\nerror: ${e.runtimeType} - ${e.toString()}\nstack: $stackTrace\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {}
      return [];
    }
  }

  /// Get detailed list of processed bills for a member
  Future<List<Map<String, dynamic>>> getUserProcessedBills(
    String userId, {
    int limit = 10,
    int offset = 0,
  }) async {
    try {
      _logger.i('Fetching processed bills for user: $userId');

      final response = await SupabaseService.instance.client
          .from('processed_bills')
          .select('''
            id,
            original_total,
            discount_amount,
            discounted_total,
            partner_id,
            processed_at,
            created_at,
            receipt_data
          ''')
          .eq('user_id', userId)
          .order('processed_at', ascending: false)
          .range(offset, offset + limit - 1);

      _logger.d('Processed bills response: ${response.length} bills found');
      return List<Map<String, dynamic>>.from(response);
    } catch (e, stackTrace) {
      _logger.e('Error fetching processed bills for $userId: $e');
      try {
        final file = File(
          '${Directory.systemTemp.path}/local_lekker_receipt_errors.log',
        );
        final now = DateTime.now().toIso8601String();
        file.writeAsStringSync(
          '\n----\ntimestamp: $now\ncontext: getUserProcessedBills\nuserId: $userId\nerror: ${e.runtimeType} - ${e.toString()}\nstack: $stackTrace\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {}
      return [];
    }
  }

  /// Get partner name from partner_id (could be enhanced to fetch from businesses table)
  Future<String> getPartnerName(String partnerId) async {
    try {
      final response = await SupabaseService.instance.client
          .from('businesses')
          .select('business_name')
          .eq('id', partnerId)
          .maybeSingle();

      if (response != null) {
        return response['business_name'] ?? 'Unknown Partner';
      }
      return 'Unknown Partner';
    } catch (e, stackTrace) {
      _logger.e('Error fetching partner name for $partnerId: $e');
      try {
        final file = File(
          '${Directory.systemTemp.path}/local_lekker_receipt_errors.log',
        );
        final now = DateTime.now().toIso8601String();
        file.writeAsStringSync(
          '\n----\ntimestamp: $now\ncontext: getPartnerName\npartnerId: $partnerId\nerror: ${e.runtimeType} - ${e.toString()}\nstack: $stackTrace\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {}
      return 'Unknown Partner';
    }
  }
}
