import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/discount.dart';
import '../../models/deal_schedule.dart';
import '../../services/deal_authorization_service.dart';
import '../../services/discount_service.dart';
import '../../services/supabase_service.dart';
import '../../services/admin_engagement_service.dart';
import '../../services/in_app_payment_availability_service.dart';
import 'deal_selection_page.dart'; // Import for BillDiscountDialog
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/branded_app_bar.dart';
import '../../widgets/website_redirect_overlay.dart';
import '../../widgets/restaurant_deal_badge.dart';
import '../members/restaurant_deal_request_page.dart';

class TrustedPartnerShopPage extends StatefulWidget {
  final Map<String, dynamic> partner;

  const TrustedPartnerShopPage({super.key, required this.partner});

  @override
  State<TrustedPartnerShopPage> createState() => _TrustedPartnerShopPageState();
}

class _TrustedPartnerShopPageState extends State<TrustedPartnerShopPage> {
  final DiscountService _discountService = DiscountService();
  List<Discount> _discounts = [];
  bool _isLoading = true;
  String? _error;

  // Brand colors for deal cards
  // Request button: Pantone 340 C (#007749)
  static const Color _kRequestGreen = Color(0xFF007749);
  // 50% lighter shade of the request green for all other green accents
  static const Color _kAccentGreen = Color(0xFF7FBBA4);
  // Card background: light grey
  static const Color _kCardBg = Color(0xFFF5F5F7);

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      print('🔍 DEBUG: Partner data received:');
      print('  - facebook_handle: ${widget.partner['facebook_handle']}');
      print('  - instagram_handle: ${widget.partner['instagram_handle']}');
      print('  - website_url: ${widget.partner['website_url']}');
      print('  - business_email: ${widget.partner['business_email']}');
    }
    _loadDiscounts();
  }

  Future<void> _loadDiscounts() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      if (kDebugMode) {
        print('🔍 Loading discounts for partner: ${widget.partner['name']}');
      }
      if (kDebugMode) {
        print('🔍 Owner member ID: ${widget.partner['owner_member_id']}');
      }

      final ownerMemberId = widget.partner['owner_member_id'];
      if (ownerMemberId == null || ownerMemberId.toString().isEmpty) {
        throw Exception(
          'No owner_member_id found for partner "${widget.partner['name']}"',
        );
      }

      // Use the same method as browse deals page - this is known to work
      await _discountService.fixDiscountVisibility();

      final allDeals = await _discountService
          .getAllActiveDiscountsWithTrustedPartners();

      // Once-off deals must disappear for a member after they have been
      // successfully paid/redeemed. Load this member's completed once-off
      // deal ids so they can be hidden below (mirrors Browse Deals behaviour).
      final currentUser = SupabaseService.instance.getCurrentUser();
      final memberId = currentUser?.id;
      Set<String> completedOnceOffDealIds = <String>{};
      if (memberId != null) {
        try {
          completedOnceOffDealIds =
              await _discountService.getCompletedDealIdsForMember(memberId);
        } catch (e) {
          // Fail open: if this lookup fails we still show deals; the
          // deal-authorization service blocks re-redeeming a once-off deal.
          if (kDebugMode) {
            print('⚠️ Failed to load completed once-off deals: $e');
          }
        }
      }

      if (kDebugMode) {
        print('🔍 Total active deals across all partners: ${allDeals.length}');
      }

      // Filter for this specific partner
      final partnerDeals = allDeals.where((deal) {
        // Match by owner_member_id (trusted_partner_id)
        return deal['trusted_partner_id'] == ownerMemberId;
      }).toList();

      if (kDebugMode) {
        print(
          '📊 Found ${partnerDeals.length} active deals for ${widget.partner['name']}',
        );
      }

      if (partnerDeals.isNotEmpty) {
        if (kDebugMode) {
          print('🔍 First deal data: ${partnerDeals.first}');
        }
      }

      // Convert to Discount objects
      final discounts = partnerDeals
          .map((deal) => Discount.fromJson(deal))
          .toList();

      if (kDebugMode) {
        print('✅ Converted to ${discounts.length} Discount objects');
      }

      // Filter by schedule - only show deals that are available now
      final availableDiscounts = discounts.where((discount) {
        // Hide once-off deals this member has already redeemed.
        if (discount.isOnceOff &&
            completedOnceOffDealIds.contains(discount.id)) {
          if (kDebugMode) {
            print(
              '⏰ Hiding once-off deal "${discount.name}" - already redeemed',
            );
          }
          return false;
        }

        if (discount.scheduleData == null || discount.scheduleData!.isEmpty) {
          // No schedule = always available
          return true;
        }

        try {
          final schedule = DealSchedule.fromJson(discount.scheduleData!);
          final isAvailable = schedule.isAvailableNow();

          if (kDebugMode && !isAvailable) {
            print(
              '⏰ Hiding scheduled deal "${discount.name}" - not available now',
            );
          }

          return isAvailable;
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Error parsing schedule for "${discount.name}": $e');
          }
          // If schedule parsing fails, show the deal
          return true;
        }
      }).toList();

      if (kDebugMode) {
        print(
          '✅ Filtered to ${availableDiscounts.length} available deals (from ${discounts.length} total)',
        );
      }

      if (availableDiscounts.isNotEmpty) {
        if (kDebugMode) {
          print(
            '✅ First available discount: ${availableDiscounts.first.name} - ${availableDiscounts.first.description}',
          );
        }
      }

      if (mounted) {
        setState(() {
          _discounts = availableDiscounts;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ Error loading discounts: $e');
      }
      if (kDebugMode) {
        print('❌ Stack trace: $stackTrace');
      }
      if (mounted) {
        setState(() {
          _error = 'Failed to load discounts: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _openDeal(BuildContext context, Discount discount) {
    if (discount.isWebsiteRedirect) {
      openWebsiteRedirectDeal(
        context,
        dealId: discount.id,
        trustedPartnerId: discount.trustedPartnerId,
        partnerName: (widget.partner['name'] as String?) ?? 'Trusted Partner',
        websiteUrl: widget.partner['website_url'] as String?,
        logoUrl: widget.partner['logo_url'] as String?,
      );
    } else if (discount.isBookingRedirect) {
      openBookingRedirectDeal(
        context,
        dealId: discount.id,
        trustedPartnerId: discount.trustedPartnerId,
        partnerName: (widget.partner['name'] as String?) ?? 'Trusted Partner',
        bookingUrl: discount.bookingUrl,
        logoUrl: widget.partner['logo_url'] as String?,
      );
    } else if (discount.isRestaurantDeal) {
      if (discount.restaurantConfig == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please update the app to use this deal.'),
          ),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RestaurantDealRequestPage(
            discount: discount,
            partnerName: widget.partner['name'] as String?,
          ),
        ),
      );
    } else if (discount.isBillDiscount) {
      _showBillDiscountDialog(context, discount);
    } else {
      _showItemDealDialog(context, discount);
    }
  }

  void _showBillDiscountDialog(BuildContext context, Discount discount) {
    // Create a deal map similar to what browse deals page uses
    final deal = discount.toJson();
    deal['trusted_partners'] = {
      'business_name': widget.partner['name'],
      'business_id': widget.partner['id'] ?? widget.partner['business_id'],
    };

    showDialog(
      context: context,
      builder: (context) => BillDiscountDialog(
        discount: discount,
        trustedPartnerName: widget.partner['name'] ?? 'Unknown Partner',
        deal: deal,
      ),
    );
  }

  void _showItemDealDialog(BuildContext context, Discount discount) {
    unawaited(AdminEngagementService().recordDealOpen(discount.id));
    int quantity = discount.isWeightBased ? 100 : 1;
    double totalPrice = discount.isWeightBased
        ? (discount.dealPrice * quantity) / 1000
        : discount.dealPrice * quantity;
    double totalSavings = discount.isWeightBased
        ? (discount.savings * quantity) / 1000
        : discount.savings * quantity;

    final TextEditingController priceController = TextEditingController();
    double? enteredPrice;
    double? discountedPrice;
    double? savingsAmount;
    String? selectedPaymentMethod;
    final availabilityService = InAppPaymentAvailabilityService();
    bool? inAppAvailable = availabilityService.cachedAvailability(discount.id);
    bool dialogOpen = true;
    StateSetter? setDialogState;
    final partnerName = widget.partner['name'] as String?;

    if (inAppAvailable == null) {
      unawaited(
        availabilityService.isAvailableForDiscount(discount.id).then((value) {
          inAppAvailable = value;
          if (dialogOpen) setDialogState?.call(() {});
        }),
      );
    }

    Future<void> switchToPayInStore(BuildContext dialogContext) async {
      inAppAvailable = false;
      if (dialogOpen) {
        setDialogState?.call(() => selectedPaymentMethod = 'pos');
      }
      await availabilityService.showUnavailableDialog(
        dialogContext,
        discountId: discount.id,
        partnerName: partnerName,
      );
    }

    Future<void> selectPaymentMethod(
      BuildContext dialogContext,
      String? value,
    ) async {
      if (value != 'in_app') {
        setDialogState?.call(() => selectedPaymentMethod = value);
        return;
      }
      final available = inAppAvailable ??
          await availabilityService.isAvailableForDiscount(discount.id);
      if (!dialogOpen) return;
      if (available) {
        setDialogState?.call(() {
          inAppAvailable = true;
          selectedPaymentMethod = 'in_app';
        });
      } else if (dialogContext.mounted) {
        await switchToPayInStore(dialogContext);
      }
    }

    void recalculateTotals() {
      if (discount.isPercentItem) {
        final price = double.tryParse(priceController.text);
        if (price != null && price > 0) {
          enteredPrice = price;
          final discountAmount = price * (discount.percentage / 100);
          discountedPrice = price - discountAmount;
          savingsAmount = discountAmount * quantity;
          totalPrice = discountedPrice! * quantity;
          totalSavings = savingsAmount!;
        } else {
          enteredPrice = null;
          discountedPrice = null;
          savingsAmount = null;
          totalPrice = 0;
          totalSavings = 0;
        }
      } else if (discount.isWeightBased) {
        // Weight-based: quantity is in grams, convert to kg for price calc
        final quantityInKg = quantity / 1000.0;
        totalPrice = discount.dealPrice * quantityInKg;
        totalSavings = discount.savings * quantityInKg;
      } else {
        // Regular deals: straight multiplication
        totalPrice = discount.dealPrice * quantity;
        totalSavings = discount.savings * quantity;
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          setDialogState = setState;
          return AlertDialog(
            title: Text(discount.name),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.partner['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (discount.isPercentItem) ...[
                      const Text(
                        'Enter Item Price',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Price before discount (R)',
                          hintText: 'e.g., 199.99',
                          border: OutlineInputBorder(),
                          prefixText: 'R ',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            recalculateTotals();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (enteredPrice != null && discountedPrice != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _kAccentGreen.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _kAccentGreen),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Original price:',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  Text(
                                    'R${enteredPrice!.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      decoration: TextDecoration.lineThrough,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'After ${discount.percentage.toStringAsFixed(0)}% off:',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'R${discountedPrice!.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _kAccentGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                    Row(
                      children: [
                        Text(
                          discount.isWeightBased ? 'Weight:' : 'Qty:',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            discount.isWeightBased
                                ? '${quantity}g (${(quantity / 1000.0).toStringAsFixed(1)}kg)'
                                : quantity.toString(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: (discount.isWeightBased ? quantity > 100 : quantity > 1)
                              ? () {
                                  setState(() {
                                    if (discount.isWeightBased) {
                                      quantity -= 100;
                                    } else {
                                      quantity--;
                                    }
                                    recalculateTotals();
                                  });
                                }
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            setState(() {
                              if (discount.isWeightBased) {
                                quantity += 100;
                              } else {
                                quantity++;
                              }
                              recalculateTotals();
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Price:'),
                        Text('R${totalPrice.toStringAsFixed(2)}'),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Savings:'),
                        Text('R${totalSavings.toStringAsFixed(2)}'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text(
                          'Payment Method',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '*',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade600,
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'Choose how you will pay for this deal',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    RadioListTile<String>(
                      value: 'in_app',
                      groupValue: selectedPaymentMethod,
                      onChanged: (value) =>
                          selectPaymentMethod(context, value),
                      activeColor: _kRequestGreen,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        'In-App Payment',
                        style: inAppAvailable == false
                            ? const TextStyle(color: Colors.grey)
                            : null,
                      ),
                      subtitle: Text(
                        inAppAvailable == false
                            ? 'Not available for this partner yet - please pay in store'
                            : 'Pay securely in the app after the partner approves',
                      ),
                    ),
                    RadioListTile<String>(
                      value: 'pos',
                      groupValue: selectedPaymentMethod,
                      onChanged: (value) =>
                          setState(() => selectedPaymentMethod = value),
                      activeColor: _kRequestGreen,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('POS Payment (In-Store)'),
                      subtitle: const Text(
                        'Visit the partner and pay at their counter',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: _kRequestGreen,
                          ),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  priceController.dispose();
                  Navigator.of(dialogContext).pop();
                },
                style: TextButton.styleFrom(
                  foregroundColor: _kRequestGreen,
                ),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed:
                    ((discount.isPercentItem &&
                            (enteredPrice == null || enteredPrice! <= 0)) ||
                        selectedPaymentMethod == null)
                    ? null
                    : () async {
                        if (discount.isPercentItem &&
                            (enteredPrice == null || enteredPrice! <= 0)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid item price'),
                            ),
                          );
                          return;
                        }

                        if (selectedPaymentMethod == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please select a payment method',
                              ),
                            ),
                          );
                          return;
                        }

                        try {
                          final currentUser =
                              SupabaseService.instance.client.auth.currentUser;
                          if (currentUser == null) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('User not authenticated'),
                                ),
                              );
                            }
                            return;
                          }

                          final dealAuthService = DealAuthorizationService();
                          await dealAuthService.requestDealAuthorization(
                            memberId: currentUser.id,
                            discountId: discount.id,
                            paymentMethod: selectedPaymentMethod!,
                            amount: totalPrice,
                            quantity: quantity,
                            memberEnteredPrice: discount.isPercentItem ? enteredPrice : null,
                            appliedDiscountAmount: totalSavings > 0 ? totalSavings : null,
                            dealType: discount.dealType,
                            dealSnapshot: discount.toJson(),
                            notes: discount.isPercentItem
                                ? 'Item deal request: ${discount.itemName} x$quantity (Price: R${enteredPrice!.toStringAsFixed(2)}, ${discount.percentage.toStringAsFixed(0)}% off)'
                                : discount.isWeightBased
                                    ? 'Weight deal request: ${discount.itemName} ${quantity}g'
                                    : 'Item deal request: ${discount.itemName} x$quantity',
                          );

                          if (mounted) {
                            priceController.dispose();
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Deal authorization request submitted',
                                ),
                                backgroundColor: _kRequestGreen,
                              ),
                            );
                          }
                        } catch (e) {
                          if (InAppPaymentAvailabilityService.isUnavailableError(
                            e,
                          )) {
                            if (context.mounted) {
                              await switchToPayInStore(context);
                            }
                            return;
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to submit request: $e'),
                              ),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.shopping_cart),
                label: const Text('Request Deal'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kRequestGreen,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() => dialogOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      print(
        '🎨 Building UI - isLoading: $_isLoading, error: $_error, discounts: ${_discounts.length}',
      );
    }

    return Scaffold(
      appBar: BrandedAppBar(
        title: Text('${widget.partner['name']} Shop'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDiscounts,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Social Media & Contact Section
          _buildSocialMediaSection(),
          // Divider
          const Divider(height: 1),
          // Main content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadDiscounts,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _discounts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.local_offer, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          'No discounts available',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.partner['name']} hasn\'t added any discounts yet',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _discounts.length,
                    itemBuilder: (context, index) {
                      final discount = _discounts[index];
                      final hasImage =
                          discount.imageUrl != null &&
                          discount.imageUrl!.isNotEmpty;

                      return Container(
                        margin: const EdgeInsets.only(
                          bottom: 16,
                          left: 2,
                          right: 2,
                          top: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _kCardBg,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            // Soft ambient shadow
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 6,
                              spreadRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                            // Deeper drop shadow for floating effect
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 18,
                              spreadRadius: 0,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                            if (discount.isActive) {
                              _openDeal(context, discount);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'This discount is currently inactive',
                                  ),
                                ),
                              );
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Deal Image - Left Side (Full Height)
                                if (hasImage)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      discount.imageUrl!,
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Container(
                                              width: 120,
                                              height: 120,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    Colors.blue.shade300,
                                                    Colors.purple.shade300,
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                discount.isBillDiscount
                                                    ? Icons.receipt_long
                                                    : Icons.local_offer,
                                                size: 48,
                                                color: Colors.white70,
                                              ),
                                            );
                                          },
                                      loadingBuilder:
                                          (context, child, loadingProgress) {
                                            if (loadingProgress == null) {
                                              return child;
                                            }
                                            return Container(
                                              width: 120,
                                              height: 120,
                                              color: Colors.grey.shade200,
                                              child: const Center(
                                                child: SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                              ),
                                            );
                                          },
                                    ),
                                  )
                                else
                                  Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.blue.shade400,
                                          Colors.purple.shade400,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      discount.isBillDiscount
                                          ? Icons.receipt_long
                                          : Icons.local_offer,
                                      size: 48,
                                      color: Colors.white70,
                                    ),
                                  ),

                                const SizedBox(width: 12),

                                // Deal Information - Right Side
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Deal Name
                                      Text(
                                        discount.name,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                          decoration: discount.isActive
                                              ? null
                                              : TextDecoration.lineThrough,
                                        ),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),

                                      if (discount.offersDelivery) ...[
                                        _buildDeliveryBadge(
                                          isFree: discount.isFreeDelivery,
                                        ),
                                        const SizedBox(height: 8),
                                      ],

                                      // Deal Details - Compact
                                      if (discount.isWebsiteRedirect)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF0E5BA0,
                                            ).withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.language,
                                                size: 14,
                                                color: Color(0xFF0E5BA0),
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'Visit Website',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF0E5BA0),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else if (discount.isBookingRedirect)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF0E5BA0,
                                            ).withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.sports_tennis,
                                                size: 14,
                                                color: Color(0xFF0E5BA0),
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'Book Now',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF0E5BA0),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else if (discount.isRestaurantDeal)
                                        RestaurantDealBadge(
                                          dealType: discount.dealType,
                                          customData: discount.customData,
                                          scheduleData: discount.scheduleData,
                                        )
                                      else if (discount.isBillDiscount)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _kAccentGreen.withOpacity(
                                              0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: _kAccentGreen,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.discount,
                                                size: 14,
                                                color: _kAccentGreen,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                discount.percentage > 0
                                                    ? '${discount.percentage.toStringAsFixed(0)}% off bill'
                                                    : 'R${discount.fixedAmount?.toStringAsFixed(2)} off bill',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: _kAccentGreen,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            if (discount.isPercentItem) ...[
                                              Text(
                                                'Member enters price',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontStyle: FontStyle.italic,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: _kAccentGreen
                                                      .withOpacity(0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '${discount.percentage.toStringAsFixed(0)}% OFF',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: _kAccentGreen,
                                                  ),
                                                ),
                                              ),
                                            ] else if (discount
                                                .isFreeDelivery) ...[
                                              // No price reduction; the saving is the delivery.
                                              Text(
                                                'R${discount.itemPrice.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: _kAccentGreen,
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: _kAccentGreen
                                                      .withValues(alpha: 0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'DELIVERY FREE',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: _kAccentGreen,
                                                  ),
                                                ),
                                              ),
                                            ] else ...[
                                              Text(
                                                discount.isWeightBased
                                                    ? 'R${discount.itemPrice.toStringAsFixed(2)}/kg'
                                                    : 'R${discount.itemPrice.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  decoration: TextDecoration
                                                      .lineThrough,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              Text(
                                                discount.isWeightBased
                                                    ? 'R${discount.dealPrice.toStringAsFixed(2)}/kg'
                                                    : 'R${discount.dealPrice.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: _kAccentGreen,
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: _kAccentGreen
                                                      .withOpacity(0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  discount.isWeightBased
                                                      ? 'Save R${discount.savings.toStringAsFixed(2)}/kg'
                                                      : 'Save R${discount.savings.toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: _kAccentGreen,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      const SizedBox(height: 8),

                                      // Status Badge & Request Button - Compact Row
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: discount.isActive
                                                  ? _kAccentGreen.withOpacity(
                                                      0.2,
                                                    )
                                                  : Colors.grey.shade200,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  discount.isActive
                                                      ? Icons.check_circle
                                                      : Icons.cancel,
                                                  size: 12,
                                                  color: discount.isActive
                                                      ? _kAccentGreen
                                                      : Colors.grey.shade600,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  discount.isActive
                                                      ? 'Active'
                                                      : 'Inactive',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: discount.isActive
                                                        ? _kAccentGreen
                                                        : Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (discount.isActive)
                                            ElevatedButton.icon(
                                              onPressed: () =>
                                                  _openDeal(context, discount),
                                              icon: Icon(
                                                discount.isWebsiteRedirect ||
                                                        discount.isBookingRedirect
                                                    ? Icons.open_in_new
                                                    : Icons.shopping_cart,
                                                size: 14,
                                              ),
                                              label: Text(
                                                discount.isWebsiteRedirect
                                                    ? 'Visit'
                                                    : discount.isBookingRedirect
                                                    ? 'Book'
                                                    : 'Request',
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: _kRequestGreen,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6,
                                                    ),
                                                textStyle: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                minimumSize: const Size(0, 28),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                          ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryBadge({bool isFree = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kRequestGreen.withValues(alpha: isFree ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kRequestGreen),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.delivery_dining, size: 14, color: _kRequestGreen),
          const SizedBox(width: 4),
          Text(
            isFree ? 'FREE delivery' : 'This partner delivers',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _kRequestGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialMediaSection() {
    final facebookHandle = widget.partner['facebook_handle'] as String?;
    final instagramHandle = widget.partner['instagram_handle'] as String?;
    final websiteUrl = widget.partner['website_url'] as String?;
    final businessEmail = widget.partner['business_email'] as String?;

    // Check if any social media handles exist
    final hasSocialMedia =
        (facebookHandle != null && facebookHandle.isNotEmpty) ||
        (instagramHandle != null && instagramHandle.isNotEmpty) ||
        (websiteUrl != null && websiteUrl.isNotEmpty) ||
        (businessEmail != null && businessEmail.isNotEmpty);

    if (!hasSocialMedia) {
      return const SizedBox.shrink(); // Don't show section if no handles
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connect with us',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (facebookHandle != null && facebookHandle.isNotEmpty)
                _buildSocialIcon(
                  icon: Icons.facebook,
                  color: const Color(0xFF1877F2), // Facebook blue
                  label: 'Facebook',
                  onTap: () => _launchUrl(_formatFacebookUrl(facebookHandle)),
                ),
              if (instagramHandle != null && instagramHandle.isNotEmpty)
                _buildSocialIcon(
                  icon: Icons.camera_alt,
                  color: const Color(0xFFE4405F), // Instagram pink
                  label: 'Instagram',
                  onTap: () => _launchUrl(_formatInstagramUrl(instagramHandle)),
                ),
              if (websiteUrl != null && websiteUrl.isNotEmpty)
                _buildSocialIcon(
                  icon: Icons.language,
                  color: const Color(0xFF4CAF50), // Green
                  label: 'Website',
                  onTap: () => _launchUrl(websiteUrl),
                ),
              if (businessEmail != null && businessEmail.isNotEmpty)
                _buildSocialIcon(
                  icon: Icons.email,
                  color: const Color(0xFFFF9800), // Orange
                  label: 'Email',
                  onTap: () => _composeEmailToPartner(businessEmail),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSocialIcon({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatFacebookUrl(String handle) {
    // Handle different Facebook URL formats
    if (handle.startsWith('http://') || handle.startsWith('https://')) {
      return handle;
    } else if (handle.startsWith('facebook.com/') ||
        handle.startsWith('www.facebook.com/')) {
      return 'https://$handle';
    } else if (handle.startsWith('@')) {
      return 'https://facebook.com/${handle.substring(1)}';
    } else {
      return 'https://facebook.com/$handle';
    }
  }

  String _formatInstagramUrl(String handle) {
    // Handle different Instagram handle formats
    if (handle.startsWith('http://') || handle.startsWith('https://')) {
      return handle;
    } else if (handle.startsWith('instagram.com/') ||
        handle.startsWith('www.instagram.com/')) {
      return 'https://$handle';
    } else if (handle.startsWith('@')) {
      return 'https://instagram.com/${handle.substring(1)}';
    } else {
      return 'https://instagram.com/$handle';
    }
  }

  Future<void> _launchUrl(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      // Don't gate on canLaunchUrl — on Android 11+ it can return false
      // even when an app (browser/Facebook) is installed and able to handle
      // the intent. Try external app first, then fall back to in-app webview
      // / platform default if the external launch fails.
      bool launched = false;
      try {
        launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        launched = false;
      }
      if (!launched) {
        try {
          launched = await launchUrl(
            uri,
            mode: LaunchMode.platformDefault,
          );
        } catch (_) {
          launched = false;
        }
      }
      if (!launched) {
        if (kDebugMode) {
          print('Could not launch $urlString');
        }
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not open $urlString')));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error launching URL: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error opening link: $e')));
      }
    }
  }

  /// Opens the user's default email client pre-filled with the partner's
  /// address, a subject built from the available deal(s), and a generic
  /// editable body the member can adjust before sending.
  Future<void> _composeEmailToPartner(String email) async {
    final partnerName =
        (widget.partner['name'] as String?)?.trim() ?? 'your business';

    // Pick the deal(s) to reference in the subject. Prefer the first active
    // deal name; otherwise use a generic enquiry subject.
    final activeDeals = _discounts.where((d) => d.isActive).toList();
    final dealForSubject = activeDeals.isNotEmpty
        ? activeDeals.first
        : (_discounts.isNotEmpty ? _discounts.first : null);

    final subject = dealForSubject != null
        ? 'Enquiry: ${dealForSubject.name}'
        : 'Enquiry from a Local Lekker member';

    final dealLine = dealForSubject != null
        ? 'I would like to enquire about your deal: "${dealForSubject.name}".'
        : 'I would like to enquire about one of your deals.';

    final body =
        'Hi $partnerName,\n\n'
        '$dealLine\n\n'
        'Could you please share more details (availability, booking, '
        'any conditions I should know about)?\n\n'
        'Thank you,\n'
        'Sent via Local Lekker';

    // Build the mailto URI manually so spaces become %20 (not '+') and
    // newlines are encoded correctly for all email clients.
    String enc(String s) => Uri.encodeComponent(s);
    final mailtoUri = Uri.parse(
      'mailto:${enc(email)}?subject=${enc(subject)}&body=${enc(body)}',
    );

    try {
      // Don't gate on canLaunchUrl for mailto: on Android — even with the
      // SENDTO/mailto <queries> entry, some devices still report false here.
      final launched = await launchUrl(
        mailtoUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No email app available to open $email'),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error launching email composer: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open email app for $email')),
        );
      }
    }
  }
}
