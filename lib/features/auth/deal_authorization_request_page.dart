import 'dart:async';
import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../models/discount.dart';
import '../../services/deal_authorization_service.dart';
import '../../services/supabase_service.dart';
import '../../services/admin_engagement_service.dart';

class DealAuthorizationRequestPage extends StatefulWidget {
  final Map<String, dynamic> deal;

  const DealAuthorizationRequestPage({super.key, required this.deal});

  @override
  State<DealAuthorizationRequestPage> createState() =>
      _DealAuthorizationRequestPageState();
}

class _DealAuthorizationRequestPageState
    extends State<DealAuthorizationRequestPage> {
  // Brand colors
  static const Color _kBrandBlue = Color(0xFF0E5BA0); // RGB 0,20,137
  static const Color _kBrandGreen = Color(0xFF3C8C44); // RGB 0,119,73
  static const Color _kBrandGreenLight = Color(0xFFE6F2EC); // light green bg

  final DealAuthorizationService _dealService = DealAuthorizationService();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _manualPriceController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _priceFocusNode = FocusNode();
  final GlobalKey _priceFieldKey = GlobalKey();
  String? _priceError;

  String? _selectedPaymentMethod; // null means not yet chosen
  bool _isSubmitting = false;
  late int _quantity; // Current quantity (items or grams)

  @override
  void initState() {
    super.initState();
    // Initialize quantity from deal data
    final discount = Discount.fromJson(widget.deal);
    unawaited(AdminEngagementService().recordDealOpen(discount.id));
    if (discount.isPercentItem && discount.requiresManualPrice) {
      final suggested = discount.itemPrice > 0
          ? discount.itemPrice.toStringAsFixed(2)
          : '';
      _manualPriceController.text = suggested;
    }
    _quantity = discount.isOnceOff
        ? 1
        : widget.deal['quantity'] as int? ?? (discount.isWeightBased ? 100 : 1);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _manualPriceController.dispose();
    _scrollController.dispose();
    _priceFocusNode.dispose();
    super.dispose();
  }

  void _scrollToPriceField() {
    // Scroll to the top where the price field is
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    // Focus the price field after scroll animation
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _priceFocusNode.requestFocus();
    });
  }

  Future<void> _submitRequest() async {
    setState(() => _isSubmitting = true);

    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final discount = Discount.fromJson(widget.deal);

      // Calculate amount based on whether it's weight-based or not
      double amount;
      double? memberEnteredPrice;
      double? appliedDiscountAmount;
      final bool isManualPercent =
          discount.isPercentItem && discount.requiresManualPrice;
      final bool isBuyGet = discount.isBuyGet;
      if (discount.isWeightBased) {
        // For weight-based: quantity is in grams, convert to kg first
        final quantityInKg = _quantity / 1000.0;
        amount = discount.dealPrice * quantityInKg;
        if (discount.savings > 0) {
          appliedDiscountAmount = discount.savings * quantityInKg;
        }
      } else if (isManualPercent) {
        memberEnteredPrice = double.tryParse(
          _manualPriceController.text.trim(),
        );

        if (memberEnteredPrice == null || memberEnteredPrice <= 0) {
          // Scroll to and focus the price input field
          setState(() => _priceError = 'Please enter the item price');
          _scrollToPriceField();
          return;
        }

        final unitDiscount = memberEnteredPrice * (discount.percentage / 100.0);
        final unitAfterDiscount = memberEnteredPrice - unitDiscount;

        amount = unitAfterDiscount * _quantity;
        appliedDiscountAmount = unitDiscount * _quantity;
      } else if (isBuyGet) {
        final totalPerCombo =
            (discount.customData?['total_price'] as num?)?.toDouble() ??
            discount.dealPrice;
        if (totalPerCombo <= 0) {
          throw Exception('This deal is missing pricing information.');
        }

        amount = totalPerCombo * _quantity;

        final basePrice = (discount.customData?['buy_item_price'] as num?)
            ?.toDouble();
        memberEnteredPrice = basePrice;
        if (basePrice != null) {
          appliedDiscountAmount = (basePrice - totalPerCombo) * _quantity;
        }
      } else {
        // For regular deals: straight multiplication
        amount = discount.dealPrice * _quantity;
        if (discount.savings > 0) {
          appliedDiscountAmount = discount.savings * _quantity;
        }
      }

      // Validate amount > 0 for all deal types
      if (amount <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This deal has no pricing set. Please contact the business.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Require explicit payment method selection
      if (_selectedPaymentMethod == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a payment method before submitting.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
            ),
          );
        }
        return;
      }

      await _dealService.requestDealAuthorization(
        memberId: user.id,
        discountId: discount.id,
        paymentMethod: _selectedPaymentMethod!,
        amount: amount,
        quantity: _quantity,
        memberEnteredPrice: memberEnteredPrice,
        appliedDiscountAmount: appliedDiscountAmount,
        dealType: discount.dealType,
        dealSnapshot: widget.deal,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deal authorization request submitted successfully!'),
            backgroundColor: _kBrandGreen,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to submit request: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final discount = Discount.fromJson(widget.deal);
    final trustedPartner =
        widget.deal['trusted_partners'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Request Deal Authorization'),
        backgroundColor: _kBrandBlue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Deal details card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trustedPartner?['business_name'] ?? 'Unknown Partner',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      discount.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      discount.description,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _kBrandGreenLight,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        discount.discountDisplay,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _kBrandGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            if (discount.isPercentItem && discount.requiresManualPrice) ...[
              const Text(
                'Enter Item Price',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter the price you\'ll pay so we can calculate your ${discount.percentage.toStringAsFixed(0)}% discount',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              TextField(
                key: _priceFieldKey,
                controller: _manualPriceController,
                focusNode: _priceFocusNode,
                decoration: InputDecoration(
                  labelText: 'Price before discount (R)',
                  hintText: 'e.g., 199.99',
                  border: const OutlineInputBorder(),
                  prefixText: 'R ',
                  errorText: _priceError,
                  errorStyle: const TextStyle(color: Colors.red),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) {
                  if (_priceError != null) {
                    setState(() => _priceError = null);
                  }
                  setState(() {}); // Rebuild to update total amount display
                },
              ),
              const SizedBox(height: 16),
            ],

            // Quantity
            const Text(
              'Quantity',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final discount = Discount.fromJson(widget.deal);
                final isWeightBased = discount.isWeightBased;

                // Once-off: fixed quantity of 1, hide selector
                if (discount.isOnceOff) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: const [
                          Text(
                            'Items:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            '1 (once-off deal)',
                            style: TextStyle(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Text(
                          isWeightBased ? 'Weight:' : 'Items:',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    if (isWeightBased) {
                                      // Decrement by 100g, minimum 100g
                                      if (_quantity > 100) {
                                        _quantity -= 100;
                                      }
                                    } else {
                                      // Decrement by 1, minimum 1
                                      if (_quantity > 1) {
                                        _quantity -= 1;
                                      }
                                    }
                                  });
                                },
                                icon: const Icon(Icons.remove),
                                iconSize: 18,
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                              ),
                              Container(
                                width: isWeightBased ? 60 : 40,
                                alignment: Alignment.center,
                                child: Text(
                                  isWeightBased
                                      ? '${_quantity}g'
                                      : _quantity.toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    if (isWeightBased) {
                                      // Increment by 100g
                                      _quantity += 100;
                                    } else {
                                      // Increment by 1
                                      _quantity += 1;
                                    }
                                  });
                                },
                                icon: const Icon(Icons.add),
                                iconSize: 18,
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Deal total based on quantity
            const Text(
              'Deal Total',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final discount = Discount.fromJson(widget.deal);
                final isWeightBased = discount.isWeightBased;

                // Calculate total price and savings based on deal type
                double totalPrice;
                double totalSavings;
                double displayQuantity;
                String quantityLabel;

                if (isWeightBased) {
                  // For weight-based: quantity is in grams, convert to kg
                  displayQuantity = _quantity / 1000.0;
                  quantityLabel = '${displayQuantity.toStringAsFixed(1)}kg';
                  totalPrice = discount.dealPrice * displayQuantity;
                  totalSavings = discount.savings * displayQuantity;
                } else {
                  // For regular deals
                  displayQuantity = _quantity.toDouble();
                  quantityLabel = '$_quantity × ${discount.itemName}';

                  if (discount.isPercentItem && discount.requiresManualPrice) {
                    final manualPrice =
                        double.tryParse(_manualPriceController.text.trim()) ??
                        0.0;
                    final unitDiscount =
                        manualPrice * (discount.percentage / 100.0);
                    final unitAfterDiscount = manualPrice - unitDiscount;
                    totalPrice = unitAfterDiscount * _quantity;
                    totalSavings = unitDiscount * _quantity;
                  } else if (discount.isBuyGet) {
                    final totalPerCombo =
                        (discount.customData?['total_price'] as num?)
                            ?.toDouble() ??
                        discount.dealPrice;
                    final basePrice =
                        (discount.customData?['buy_item_price'] as num?)
                            ?.toDouble();
                    totalPrice = totalPerCombo * _quantity;
                    if (basePrice != null) {
                      final unitSaving = basePrice - totalPerCombo;
                      totalSavings = unitSaving > 0
                          ? unitSaving * _quantity
                          : 0.0;
                    } else {
                      totalSavings = discount.savings * _quantity;
                    }
                  } else {
                    totalPrice = discount.dealPrice * _quantity;
                    totalSavings = discount.savings * _quantity;
                  }
                }

                return Card(
                  color: _kBrandGreenLight,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Quantity:',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            Text(
                              isWeightBased
                                  ? '$quantityLabel × ${discount.itemName}'
                                  : quantityLabel,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Unit Price:',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            Text(
                              () {
                                if (discount.isPercentItem &&
                                    discount.requiresManualPrice) {
                                  final manualPrice =
                                      double.tryParse(
                                        _manualPriceController.text.trim(),
                                      ) ??
                                      0.0;
                                  final unitDiscount =
                                      manualPrice *
                                      (discount.percentage / 100.0);
                                  final unitAfterDiscount =
                                      manualPrice - unitDiscount;
                                  return 'R${unitAfterDiscount.toStringAsFixed(2)}';
                                } else if (isWeightBased) {
                                  return 'R${discount.dealPrice.toStringAsFixed(2)}/kg';
                                } else {
                                  return 'R${discount.dealPrice.toStringAsFixed(2)}';
                                }
                              }(),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        if (discount.isPercentItem &&
                            discount.requiresManualPrice) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Original Price:',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              Text(
                                'R${(double.tryParse(_manualPriceController.text.trim()) ?? 0.0).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  decoration: TextDecoration.lineThrough,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Amount:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'R${totalPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _kBrandGreen,
                              ),
                            ),
                          ],
                        ),
                        if (totalSavings > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'You Save:',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              Text(
                                'R${totalSavings.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: _kBrandGreen,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Payment method selection
            Row(
              children: [
                const Text(
                  'Payment Method',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                Text(
                  '*',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Choose how you will pay for this deal',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            _buildPaymentMethodCard(
              'in_app',
              'In-App Payment',
              'Pay securely through the app after the partner approves your request',
              Icons.phone_android,
            ),
            const SizedBox(height: 12),
            _buildPaymentMethodCard(
              'pos',
              'POS Payment (In-Store)',
              'Visit the partner\'s store and pay at their counter',
              Icons.store,
            ),

            const SizedBox(height: 24),

            // Notes (optional)
            const Text(
              'Additional Notes (Optional)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Any special requests or notes...',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 32),

            // Submit button
            Padding(
              padding: const EdgeInsets.only(bottom: 70),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitRequest,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: _kBrandBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Submit Authorization Request',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodCard(
    String method,
    String title,
    String description,
    IconData icon,
  ) {
    final isSelected = _selectedPaymentMethod == method;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? _kBrandBlue
              : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selectedPaymentMethod = method),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 32,
                color: isSelected
                    ? _kBrandBlue
                    : Colors.grey.shade600,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? _kBrandBlue
                            : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? _kBrandBlue
                        : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kBrandBlue,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
