import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:logger/logger.dart';
import '../../core/constants/deal_categories.dart';
import '../../models/discount.dart';
import '../../models/deal_schedule.dart';
import '../../services/discount_service.dart';
import '../../services/supabase_service.dart';
import '../../services/website_redirect_service.dart';
import '../../widgets/deal_schedule_widget.dart';
import '../../widgets/liquor_licence_warning.dart';
import '../admin/website_redirect_deal_dialog.dart';
import '../admin/booking_redirect_deal_dialog.dart';
import '../business/restaurant_deal_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';

const Color _freshLocalMenuBackground = Color(0xFFE8F5D0);
const Color _freshLocalMenuText = Color(0xFF416D1B);
const Color _localSipsMenuBackground = Color(0xFFF4DDE1);
const Color _localSipsMenuText = Color(0xFF722F37);
const Color _localEatsMenuBackground = Color(0xFFFFE2D5);
const Color _localEatsMenuText = Color(0xFFB33D20);
const Color _locallyActiveMenuBackground = Color(0xFFD6ECFB);
const Color _locallyActiveMenuText = Color(0xFF01579B);

DropdownMenuItem<String> _buildCategoryMenuItem(String category) {
  final isFreshLocal = category == kFreshLocalCategory;
  final isLocalSips = category == kLocalSipsCategory;
  final isLocalEats = category == kLocalEatsCategory;
  final isLocallyActive = category == kLocallyActiveCategory;
  final isHighlighted =
      isFreshLocal || isLocalSips || isLocalEats || isLocallyActive;

  return DropdownMenuItem<String>(
    value: category,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: isHighlighted
          ? BoxDecoration(
              color: isFreshLocal
                  ? _freshLocalMenuBackground
                  : isLocalSips
                  ? _localSipsMenuBackground
                  : isLocalEats
                  ? _localEatsMenuBackground
                  : _locallyActiveMenuBackground,
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      child: Text(
        category,
        style: isHighlighted
            ? TextStyle(
                color: isFreshLocal
                    ? _freshLocalMenuText
                    : isLocalSips
                    ? _localSipsMenuText
                    : isLocalEats
                    ? _localEatsMenuText
                    : _locallyActiveMenuText,
                fontWeight: FontWeight.w700,
              )
            : null,
      ),
    ),
  );
}

class DiscountManagementPage extends StatefulWidget {
  /// When non-null the page manages deals for this partner (admin flow).
  final String? trustedPartnerId;
  final String? businessName;
  final String? lockedDealCategory;
  final bool openCreateDealOnLoad;

  const DiscountManagementPage({
    super.key,
    this.trustedPartnerId,
    this.businessName,
    this.lockedDealCategory,
    this.openCreateDealOnLoad = false,
  });

  @override
  State<DiscountManagementPage> createState() => _DiscountManagementPageState();
}

class _DiscountManagementPageState extends State<DiscountManagementPage> {
  final Logger _logger = Logger();
  final DiscountService _discountService = DiscountService();
  final SupabaseService _supabaseService = SupabaseService.instance;
  bool _isLoading = true;
  bool _isCreatingDiscount = false;
  List<Discount> _discounts = [];
  bool _partnerCategoryLoaded = false;
  String? _lockedDealCategory;
  Map<String, int> _redirectClickCounts = {};

  /// Admins open this page with an explicit partner id.
  bool get _isAdminContext => widget.trustedPartnerId != null;
  @override
  void initState() {
    super.initState();
    _lockedDealCategory = widget.lockedDealCategory;
    _partnerCategoryLoaded = widget.lockedDealCategory != null;
    _loadDiscounts();
    if (!_partnerCategoryLoaded) {
      _getLockedDealCategory().then((_) {
        if (mounted) setState(() {});
      });
    }
    if (widget.openCreateDealOnLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _addDiscount();
      });
    }
  }

  /// The effective partner ID: either the explicit one (admin) or the current user.
  String get _effectivePartnerId =>
      widget.trustedPartnerId ??
      _supabaseService.client.auth.currentUser!.id;

  Future<void> _loadDiscounts() async {
    setState(() => _isLoading = true);
    try {
      final trustedPartnerId = _effectivePartnerId;
      _logger.i(
        'Loading discounts for trustedPartnerId: $trustedPartnerId',
      );
      final discounts = await _discountService.getAllTrustedPartnerDiscounts(
        trustedPartnerId,
      );
      _logger.i(
        'Fetched ${discounts.length} discounts for trustedPartnerId: $trustedPartnerId',
      );
      final clickCounts = _isAdminContext
          ? await WebsiteRedirectService().getClickCounts(
              discounts
                  .where((d) => d.isWebsiteRedirect || d.isBookingRedirect)
                  .map((d) => d.id)
                  .toList(),
            )
          : <String, int>{};
      setState(() {
        _discounts = discounts;
        _redirectClickCounts = clickCounts;
        _isLoading = false;
      });
    } catch (e) {
      _logger.e('Error loading discounts: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<String?> _getLockedDealCategory() async {
    if (_partnerCategoryLoaded) return _lockedDealCategory;

    try {
      final business = await _supabaseService.client
          .from('businesses')
          .select(
            'category, sells_fresh_produce, sells_alcohol, offers_sports_activities',
          )
          .eq('owner_member_id', _effectivePartnerId)
          .maybeSingle();
      final sellsFreshProduce = business?['sells_fresh_produce'] == true;
      final sellsAlcohol = business?['sells_alcohol'] == true;
      final offersSportsActivities =
          business?['offers_sports_activities'] == true;
        final businessCategory = business?['category'] as String?;

      _lockedDealCategory = sellsFreshProduce
          ? kFreshLocalCategory
          : sellsAlcohol
          ? kLocalSipsCategory
          : offersSportsActivities
          ? kLocallyActiveCategory
          : businessCategory != null &&
                (kLocalEatsBusinessCategories.contains(businessCategory) ||
                    businessCategory == kLocalEatsCategory)
          ? kLocalEatsCategory
          : businessCategory == kFreshLocalCategory
          ? kFreshLocalCategory
          : businessCategory == kLocalSipsCategory
          ? kLocalSipsCategory
          : businessCategory == kLocallyActiveCategory
          ? kLocallyActiveCategory
          : null;
    } catch (e) {
      _logger.w('Could not determine partner deal category: $e');
    } finally {
      _partnerCategoryLoaded = true;
    }

    return _lockedDealCategory;
  }

  Future<void> _addDiscount() async {
    if (_isCreatingDiscount) return;

    final lockedDealCategory = await _getLockedDealCategory();
    if (!mounted) return;

    // Local Eats partners may only create the restaurant deal types.
    if (lockedDealCategory == kLocalEatsCategory) {
      await _openRestaurantDealDialog(lockedDealCategory: lockedDealCategory);
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AddDiscountDialog(
        trustedPartnerId: _effectivePartnerId,
        lockedDealCategory: lockedDealCategory,
      ),
    );
    if (result != null) {
      try {
        if (_isCreatingDiscount) return;
        setState(() => _isCreatingDiscount = true);

        // Ensure we have a valid trustedPartnerId
        final trustedPartnerId = result['trustedPartnerId'] as String?;
        if (trustedPartnerId == null || trustedPartnerId.isEmpty) {
          throw Exception('Invalid trusted partner ID');
        }

        await _discountService.createDiscount(
          trustedPartnerId: trustedPartnerId,
          name: result['name'],
          description: result['description'],
          itemName: result['itemName'],
          itemPrice: result['itemPrice'],
          percentage: result['percentage'],
          fixedAmount: result['fixedAmount'],
          dealType: result['dealType'],
          customData: result['customData'],
          requiresManualPrice: result['requiresManualPrice'],
          isWeightBased: result['isWeightBased'] ?? false,
          isBillDiscount: result['isBillDiscount'] ?? false,
          isOnceOff: result['isOnceOff'] ?? false,
          billDiscountData: result['billDiscountData'],
          imageUrl: result['imageUrl'],
          scheduleData: result['scheduleData'],
          dealCategory: result['dealCategory'] ?? 'Other',
          offersDelivery: result['offersDelivery'] ?? false,
        );
        await _loadDiscounts();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deal added successfully'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 40, left: 16, right: 16),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add deal: $e'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
          ),
        );
      } finally {
        if (mounted) {
          setState(() => _isCreatingDiscount = false);
        }
      }
    }
  }

  Future<void> _editDiscount(Discount discount) async {
    final lockedDealCategory = await _getLockedDealCategory();
    if (!mounted) return;

    if (discount.isWebsiteRedirect) {
      if (!_isAdminContext) return;
      await _openWebsiteRedirectDialog(
        existing: discount,
        lockedDealCategory: lockedDealCategory,
      );
      return;
    }

    if (discount.isBookingRedirect) {
      if (!_isAdminContext) return;
      await _openBookingRedirectDialog(existing: discount);
      return;
    }

    if (discount.isRestaurantDeal) {
      await _openRestaurantDealDialog(
        existing: discount,
        lockedDealCategory: lockedDealCategory,
      );
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EditDiscountDialog(
        discount: discount,
        trustedPartnerId: _effectivePartnerId,
        lockedDealCategory: lockedDealCategory,
      ),
    );

    if (result != null && mounted) {
      try {
          // Update the discount with all the fields
          await _discountService.updateDiscount(
            discount.id,
            name: result['name'],
            description: result['description'],
            itemName: result['itemName'],
            itemPrice: result['itemPrice'],
            percentage: result['percentage'],
            fixedAmount: result['fixedAmount'],
            dealType: result['dealType'],
            customData: result['customData'],
            requiresManualPrice: result['requiresManualPrice'],
            billDiscountData: result['billDiscountData'],
            imageUrl: result['imageUrl'],
            scheduleData: result['scheduleData'],
            dealCategory: result['dealCategory'],
            offersDelivery: result['offersDelivery'],
            isOnceOff: result['isOnceOff'],
            updateImageUrl:
                true, // Always update imageUrl (even if null for deletion)
          );
          await _loadDiscounts();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Deal updated successfully'),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 40, left: 16, right: 16),
            ),
          );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update deal: $e'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
          ),
        );
      }
    }
  }

  Future<void> _addWebsiteRedirectDeal() async {
    final lockedDealCategory = await _getLockedDealCategory();
    if (!mounted) return;
    await _openWebsiteRedirectDialog(lockedDealCategory: lockedDealCategory);
  }

  Future<void> _addBookingRedirectDeal() async {
    await _openBookingRedirectDialog();
  }

  /// Restaurant deals are offered to food and drink partners (and admins).
  bool get _canAddRestaurantDeals =>
      _isAdminContext ||
      _lockedDealCategory == kLocalEatsCategory ||
      _lockedDealCategory == kLocalSipsCategory;

  bool get _isLocalEatsPartner => _lockedDealCategory == kLocalEatsCategory;

  Future<void> _addRestaurantDeal() async {
    final lockedDealCategory = await _getLockedDealCategory();
    if (!mounted) return;
    await _openRestaurantDealDialog(lockedDealCategory: lockedDealCategory);
  }

  Future<void> _openRestaurantDealDialog({
    Discount? existing,
    String? lockedDealCategory,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => RestaurantDealDialog(
        trustedPartnerId: _effectivePartnerId,
        existing: existing,
        lockedDealCategory: lockedDealCategory,
      ),
    );
    if (saved != true || !mounted) return;
    await _loadDiscounts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existing == null ? 'Restaurant deal added' : 'Restaurant deal updated',
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
      ),
    );
  }

  Future<void> _openBookingRedirectDialog({Discount? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => BookingRedirectDealDialog(
        trustedPartnerId: _effectivePartnerId,
        existing: existing,
      ),
    );
    if (saved != true || !mounted) return;
    await _loadDiscounts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existing == null ? 'Booking deal added' : 'Booking deal updated',
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
      ),
    );
  }

  Future<void> _openWebsiteRedirectDialog({
    Discount? existing,
    String? lockedDealCategory,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => WebsiteRedirectDealDialog(
        trustedPartnerId: _effectivePartnerId,
        existing: existing,
        lockedDealCategory: lockedDealCategory,
      ),
    );
    if (saved != true || !mounted) return;
    await _loadDiscounts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existing == null ? 'Website deal added' : 'Website deal updated',
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
      ),
    );
  }

  Future<void> _deleteDiscount(String discountId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Deal'),
        content: const Text('Are you sure you want to delete this deal?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _discountService.deleteDiscount(discountId);
        await _loadDiscounts();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deal deleted successfully'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 40, left: 16, right: 16),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete deal: $e'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
          ),
        );
      }
    }
  }

  Future<void> _toggleDiscountActive(Discount discount) async {
    try {
      await _discountService.updateDiscount(
        discount.id,
        isActive: !discount.isActive,
      );

      // Update local state
      setState(() {
        final index = _discounts.indexWhere((d) => d.id == discount.id);
        if (index != -1) {
          _discounts[index] = Discount(
            id: discount.id,
            trustedPartnerId: discount.trustedPartnerId,
            name: discount.name,
            description: discount.description,
            itemName: discount.itemName,
            itemPrice: discount.itemPrice,
            percentage: discount.percentage,
            fixedAmount: discount.fixedAmount,
            dealType: discount.dealType,
            customData: discount.customData,
            dealCategory: discount.dealCategory,
            isActive: !discount.isActive,
            createdAt: discount.createdAt,
            updatedAt: DateTime.now(),
            imageUrl: discount.imageUrl, // Preserve image URL
            isWeightBased: discount.isWeightBased,
            isBillDiscount: discount.isBillDiscount,
            billDiscountData: discount.billDiscountData,
          );
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Deal ${discount.isActive ? 'deactivated' : 'activated'}',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update deal status'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 40, left: 16, right: 16),
          ),
        );
      }
    }
  }

  String _getScheduleDisplayText(Map<String, dynamic> scheduleData) {
    try {
      final schedule = DealSchedule.fromJson(scheduleData);

      if (schedule.type == ScheduleType.weekly) {
        return '🕒 ${schedule.describe()}';
      }
      if (schedule.type == ScheduleType.dateRange) {
        if (schedule.startDate != null && schedule.endDate != null) {
          final startStr =
              '${schedule.startDate!.day} ${_getMonthAbbr(schedule.startDate!.month)}';
          final endStr =
              '${schedule.endDate!.day} ${_getMonthAbbr(schedule.endDate!.month)}';
          return '📅 $startStr - $endStr';
        }
      } else if (schedule.type == ScheduleType.dayOfWeek) {
        final days = schedule.dayOfWeeks.isNotEmpty
            ? schedule.dayOfWeeks
            : (schedule.dayOfWeek == null ? const [] : [schedule.dayOfWeek!]);
        if (days.isNotEmpty) {
          final dayName = days.map((day) => day.displayName).join(', ');
          if (schedule.isRecurring) {
            return '🔄 Every $dayName';
          } else {
            return '📆 $dayName Only';
          }
        }
      }
      return '📅 Scheduled';
    } catch (e) {
      return '📅 Scheduled';
    }
  }

  String _getMonthAbbr(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: Text(widget.businessName != null
            ? 'Deals – ${widget.businessName}'
            : 'Discount Management'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (_isAdminContext)
                        IconButton(
                          icon: const Icon(Icons.language, size: 26),
                          tooltip: 'Add Website Deal (admin only)',
                          onPressed: _addWebsiteRedirectDeal,
                        ),
                      if (_isAdminContext &&
                          _lockedDealCategory == kLocallyActiveCategory)
                        IconButton(
                          icon: const Icon(Icons.sports_tennis, size: 26),
                          tooltip: 'Add Booking Deal (admin only)',
                          onPressed: _addBookingRedirectDeal,
                        ),
                      if (_canAddRestaurantDeals && !_isLocalEatsPartner)
                        IconButton(
                          icon: const Icon(Icons.restaurant_menu, size: 26),
                          tooltip: 'Add Restaurant Deal',
                          onPressed: _addRestaurantDeal,
                        ),
                      if (!_partnerCategoryLoaded)
                        const SizedBox.shrink()
                      else if (_isLocalEatsPartner)
                        TextButton.icon(
                          icon: const Icon(Icons.restaurant_menu),
                          label: const Text('Add Restaurant Deal'),
                          onPressed: _addDiscount,
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.add, size: 28),
                          tooltip: 'Add Deal',
                          onPressed: _addDiscount,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _buildDiscountList()),
                ],
              ),
            ),
    );
  }

  Widget _buildDiscountList() {
    if (_discounts.isEmpty) {
      return Center(
        child: Text(
          'No discounts found for this profile.',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 100,
      ), // Added bottom padding
      itemCount: _discounts.length,
      itemBuilder: (context, index) {
        final discount = _discounts[index];
        final isWeightBased = discount.isWeightBased;
        final isRedirect = discount.isWebsiteRedirect;
        final isBooking = discount.isBookingRedirect;
        final canManage = !(isRedirect || isBooking) || _isAdminContext;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Deal Image (if available)
                if (discount.imageUrl != null && discount.imageUrl!.isNotEmpty)
                  Container(
                    width: 80,
                    height: 80,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        discount.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.error, color: Colors.grey),
                          );
                        },
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              discount.name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: discount.isActive
                                    ? Colors.black
                                    : Colors.grey,
                              ),
                            ),
                          ),
                          Switch(
                            value: discount.isActive,
                            onChanged: canManage
                                ? (value) => _toggleDiscountActive(discount)
                                : null,
                            activeThumbColor: Colors.green,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Description
                      Text(
                        discount.description,
                        style: TextStyle(
                          color: discount.isActive
                              ? Colors.black87
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Price info
                      Text(
                        isRedirect
                            ? 'Website Deal - opens partner website'
                            : isBooking
                            ? 'Booking Deal - opens partner booking page'
                            : discount.isRestaurantDeal
                            ? '${discount.restaurantType?.label ?? 'Restaurant Deal'} - ${discount.discountDisplay}'
                            : discount.isBuyGet
                            ? '${discount.customData?['buy_item_name'] ?? discount.itemName} + ${discount.customData?['free_item_name'] ?? 'Free Item'} - R${discount.dealPrice.toStringAsFixed(2)}'
                            : discount.isPercentItem
                            ? '${discount.itemName} - ${discount.percentage.toStringAsFixed(0)}% off'
                            : discount.isBillDiscount
                            ? 'Bill Discount - ${discount.percentage.toStringAsFixed(0)}% off'
                            : isWeightBased
                            ? '${discount.itemName} - R${discount.itemPrice.toStringAsFixed(2)}/kg → R${discount.dealPrice.toStringAsFixed(2)}/kg'
                            : '${discount.itemName} - R${discount.itemPrice.toStringAsFixed(2)} → R${discount.dealPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: discount.isActive ? Colors.green : Colors.grey,
                        ),
                      ),
                      Text(
                        isRedirect
                            ? (_isAdminContext
                                  ? '${_redirectClickCounts[discount.id] ?? 0} website visits'
                                  : 'Managed by Local Lekker')
                            : isBooking
                            ? (_isAdminContext
                                  ? '${_redirectClickCounts[discount.id] ?? 0} booking clicks'
                                  : 'Managed by Local Lekker')
                            : discount.isBuyGet
                            ? 'Get ${discount.customData?['free_item_name'] ?? 'Free Item'} free (Save R${discount.savings.toStringAsFixed(2)})'
                            : discount.isPercentItem
                            ? 'Member enters item price at checkout'
                            : discount.isBillDiscount
                            ? 'Applied to total bill at scan time'
                            : isWeightBased
                            ? 'Save R${discount.savings.toStringAsFixed(2)}/kg'
                            : 'Save R${discount.savings.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: discount.isActive ? Colors.green : Colors.grey,
                        ),
                      ),
                      // Schedule info
                      if (discount.scheduleData != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.blue.shade200,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 14,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _getScheduleDisplayText(
                                    discount.scheduleData!,
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue.shade900,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Action buttons
                      if (canManage)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () => _editDiscount(discount),
                            icon: const Icon(Icons.edit, size: 20),
                            label: const Text('Edit'),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => _deleteDiscount(discount.id),
                            icon: const Icon(
                              Icons.delete,
                              size: 20,
                              color: Colors.red,
                            ),
                            label: const Text(
                              'Delete',
                              style: TextStyle(color: Colors.red),
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
        );
      },
    );
  }
}

class AddDiscountDialog extends StatefulWidget {
  final String? trustedPartnerId;
  final String? lockedDealCategory;

  const AddDiscountDialog({
    super.key,
    this.trustedPartnerId,
    this.lockedDealCategory,
  });

  @override
  State<AddDiscountDialog> createState() => _AddDiscountDialogState();
}

enum DiscountType {
  none,
  percentage,
  fixedAmount,
  onceOff,
  weight,
  billDiscount,
  buyGet,
  percentItem,
  freeDelivery,
}

class _AddDiscountDialogState extends State<AddDiscountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _descriptionController = TextEditingController();
  final _itemNameController = TextEditingController();
  final _itemPriceController = TextEditingController();
  final _percentageController = TextEditingController();
  final _dealPriceController = TextEditingController();
  final _pricePerKgController = TextEditingController();
  final _dealPricePerKgController = TextEditingController();

  // Bill discount controllers
  final _billDiscountPercentageController = TextEditingController();
  final _billDiscountTotalController = TextEditingController();

  // Buy-Get & Percent-Item specific controllers
  final _buyItemNameController = TextEditingController();
  final _buyItemPriceController = TextEditingController();
  final _freeItemNameController = TextEditingController();
  final _freeItemPriceController = TextEditingController();
  final _totalBuyGetPriceController = TextEditingController();
  final _percentItemNameController = TextEditingController();
  final _percentDiscountController = TextEditingController();

  DiscountType _selectedType = DiscountType.none;
  bool _isOnceOff = false;
  String _selectedCategory = 'Other';
  bool _offersDelivery = false;
  double _itemPrice = 0.0;
  double _calculatedDealPrice = 0.0;
  double _savings = 0.0;
  double _pricePerKg = 0.0;
  double _dealPricePerKg = 0.0;
  double _savingsPerKg = 0.0;

  // Bill discount state
  bool _billDiscountIsPercentage = true;
  final List<Map<String, dynamic>> _exclusions = [];

  // Image upload state
  XFile? _selectedImage;
  List<int>? _imageBytes;
  bool _isUploadingImage = false;

  // Schedule state
  DealSchedule? _dealSchedule;

  // Validation state
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.lockedDealCategory ?? 'Other';
    _itemPriceController.addListener(_calculateValues);
    _percentageController.addListener(_calculateValues);
    _dealPriceController.addListener(_calculateValues);
    _pricePerKgController.addListener(_calculateValues);
    _dealPricePerKgController.addListener(_calculateValues);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _descriptionController.dispose();
    _itemNameController.dispose();
    _itemPriceController.dispose();
    _percentageController.dispose();
    _dealPriceController.dispose();
    _pricePerKgController.dispose();
    _dealPricePerKgController.dispose();
    _billDiscountPercentageController.dispose();
    _billDiscountTotalController.dispose();
    _buyItemNameController.dispose();
    _buyItemPriceController.dispose();
    _freeItemNameController.dispose();
    _freeItemPriceController.dispose();
    _totalBuyGetPriceController.dispose();
    _percentItemNameController.dispose();
    _percentDiscountController.dispose();
    super.dispose();
  }

  void _calculateValues() {
    final itemPrice = double.tryParse(_itemPriceController.text) ?? 0.0;
    setState(() {
      _itemPrice = itemPrice;

      if (_selectedType == DiscountType.percentage) {
        final percentage = double.tryParse(_percentageController.text) ?? 0.0;
        _calculatedDealPrice = itemPrice * (1 - percentage / 100);
        _savings = itemPrice - _calculatedDealPrice;
      } else if (_selectedType == DiscountType.fixedAmount ||
          _selectedType == DiscountType.onceOff) {
        final dealPrice = double.tryParse(_dealPriceController.text) ?? 0.0;
        _calculatedDealPrice = dealPrice;
        _savings = itemPrice - dealPrice;
      } else if (_selectedType == DiscountType.weight) {
        final pricePerKg = double.tryParse(_pricePerKgController.text) ?? 0.0;
        final dealPricePerKg =
            double.tryParse(_dealPricePerKgController.text) ?? 0.0;
        _pricePerKg = pricePerKg;
        _dealPricePerKg = dealPricePerKg;
        _savingsPerKg = pricePerKg - dealPricePerKg;
      }
    });
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Add New Deal',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Scrollable content
            Flexible(
              child: Form(
                key: _formKey,
                autovalidateMode: _autovalidateMode,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Comes first because it unlocks the Free Delivery type.
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _offersDelivery,
                        title: const Text('Delivery available'),
                        subtitle: const Text(
                          'Unlocks the Free Delivery deal type and shows a '
                          'delivery note to members',
                        ),
                        secondary: const Icon(Icons.delivery_dining),
                        onChanged: (value) => setState(() {
                          _offersDelivery = value;
                          // Free Delivery cannot outlive the delivery option.
                          if (!value &&
                              _selectedType == DiscountType.freeDelivery) {
                            _selectedType = DiscountType.none;
                          }
                        }),
                      ),
                      const SizedBox(height: 8),

                      // Dropdown for discount type - ALWAYS VISIBLE
                      DropdownButtonFormField<DiscountType>(
                        isExpanded: true,
                        initialValue: _selectedType,
                        decoration: const InputDecoration(
                          labelText: 'Select Discount Type',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: DiscountType.none,
                            child: Text('-- Select Type --'),
                          ),
                          const DropdownMenuItem(
                            value: DiscountType.percentage,
                            child: Text('Percentage'),
                          ),
                          const DropdownMenuItem(
                            value: DiscountType.fixedAmount,
                            child: Text('Fixed Amount'),
                          ),
                          const DropdownMenuItem(
                            value: DiscountType.weight,
                            child: Text('Weight'),
                          ),
                          const DropdownMenuItem(
                            value: DiscountType.billDiscount,
                            child: Text('Bill Discount'),
                          ),
                          const DropdownMenuItem(
                            value: DiscountType.buyGet,
                            child: Text('Buy This Get That'),
                          ),
                          const DropdownMenuItem(
                            value: DiscountType.percentItem,
                            child: Text('% Off Item (Manual Price)'),
                          ),
                          // Only offered once the partner has enabled delivery.
                          if (_offersDelivery)
                            const DropdownMenuItem(
                              value: DiscountType.freeDelivery,
                              child: Text('Free Delivery (normal price)'),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedType = value ?? DiscountType.none;
                          });
                        },
                        validator: (value) {
                          if (value == null || value == DiscountType.none) {
                            return 'Please select a discount type';
                          }
                          return null;
                        },
                      ),

                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Once-off deal'),
                        subtitle: const Text(
                          'Each member can successfully use this deal only once.',
                        ),
                        value: _isOnceOff,
                        onChanged: (value) => setState(() {
                          _isOnceOff = value ?? false;
                        }),
                      ),

                      // Deal Category is fixed for Fresh & Local and Local Sips partners.
                      const SizedBox(height: 16),
                      if (widget.lockedDealCategory != null)
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Deal Category',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            widget.lockedDealCategory!,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _selectedCategory,
                          decoration: const InputDecoration(
                            labelText: 'Deal Category',
                            hintText: 'Select a category for this deal',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final category in kDealCategories)
                              _buildCategoryMenuItem(category),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedCategory = value ?? 'Other';
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please select a category';
                            }
                            return null;
                          },
                        ),
                      LiquorLicenceWarning(
                        selectedCategory: _selectedCategory,
                      ),

                      // Only show fields if a type is selected
                      if (_selectedType != DiscountType.none) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Deal Description',
                            hintText: 'e.g., Weekend Special, Student Deal',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a deal description';
                            }
                            return null;
                          },
                        ),

                        // Bill Discount specific fields
                        if (_selectedType == DiscountType.billDiscount) ...[
                          const SizedBox(height: 16),
                          // Percentage/Total Toggle
                          Row(
                            children: [
                              const Text(
                                'Discount Type:',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: SegmentedButton<bool>(
                                  segments: const [
                                    ButtonSegment(
                                      value: true,
                                      label: Text('Percentage'),
                                    ),
                                    ButtonSegment(
                                      value: false,
                                      label: Text('Total'),
                                    ),
                                  ],
                                  selected: {_billDiscountIsPercentage},
                                  onSelectionChanged: (Set<bool> selected) {
                                    setState(
                                      () => _billDiscountIsPercentage =
                                          selected.first,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Show percentage or total field based on toggle
                          if (_billDiscountIsPercentage)
                            TextFormField(
                              controller: _billDiscountPercentageController,
                              decoration: const InputDecoration(
                                labelText: 'Discount Percentage (%)',
                                hintText: 'e.g., 10',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a percentage';
                                }
                                final percent = double.tryParse(value);
                                if (percent == null ||
                                    percent <= 0 ||
                                    percent > 100) {
                                  return 'Please enter a valid percentage (1-100)';
                                }
                                return null;
                              },
                            )
                          else
                            TextFormField(
                              controller: _billDiscountTotalController,
                              decoration: const InputDecoration(
                                labelText: 'Fixed Discount Amount (R)',
                                hintText: 'e.g., 50.00',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a discount amount';
                                }
                                final amount = double.tryParse(value);
                                if (amount == null || amount <= 0) {
                                  return 'Please enter a valid amount';
                                }
                                return null;
                              },
                            ),

                          const SizedBox(height: 16),
                          // Exclusions Section
                          _buildExclusionsSection(),
                        ],

                        const SizedBox(height: 16),

                        // Show item name and pricing fields for non-bill discount types (excluding buyGet and percentItem)
                        if (_selectedType != DiscountType.billDiscount &&
                            _selectedType != DiscountType.buyGet &&
                            _selectedType != DiscountType.percentItem) ...[
                          TextFormField(
                            controller: _itemNameController,
                            decoration: InputDecoration(
                              labelText: 'Item Name',
                              hintText: _selectedType == DiscountType.weight
                                  ? 'e.g., Apples, Tomatoes, Chicken'
                                  : 'e.g., Coffee, Burger, Pizza',
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter an item name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        // BUY-GET DEAL FIELDS
                        if (_selectedType == DiscountType.buyGet) ...[
                          const Text(
                            'Buy Item',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _buyItemNameController,
                            decoration: const InputDecoration(
                              labelText: 'Item Name (what member buys)',
                              hintText: 'e.g., Coffee',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter item name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _buyItemPriceController,
                            decoration: const InputDecoration(
                              labelText: 'Normal Price (R)',
                              hintText: 'e.g., 75.00',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter price';
                              }
                              final price = double.tryParse(value);
                              if (price == null || price <= 0) {
                                return 'Enter valid price';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Free Item',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _freeItemNameController,
                            decoration: const InputDecoration(
                              labelText: 'Item Name (what member gets free)',
                              hintText: 'e.g., Pastry',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter free item name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _freeItemPriceController,
                            decoration: const InputDecoration(
                              labelText: 'Normally Costs (R)',
                              hintText: 'e.g., 45.00',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter free item value';
                              }
                              final price = double.tryParse(value);
                              if (price == null || price <= 0) {
                                return 'Enter valid price';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                        ],

                        // PERCENT-ITEM DEAL FIELDS
                        if (_selectedType == DiscountType.percentItem) ...[
                          const Text(
                            'Member will enter the item price when requesting. Discount will be applied as a percentage off that price.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _percentDiscountController,
                            decoration: const InputDecoration(
                              labelText: 'Discount Percentage (%)',
                              hintText: 'e.g., 15',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter percentage';
                              }
                              final percent = double.tryParse(value);
                              if (percent == null ||
                                  percent <= 0 ||
                                  percent > 100) {
                                return 'Enter valid percentage (1-100)';
                              }
                              return null;
                            },
                          ),
                        ],

                        const SizedBox(height: 16),

                        // Show weight-based fields for weight type
                        if (_selectedType == DiscountType.weight) ...[
                          TextFormField(
                            controller: _pricePerKgController,
                            decoration: const InputDecoration(
                              labelText: 'R/kg Price (R/kg)',
                              hintText: 'e.g., 89.99',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter price per kg';
                              }
                              final price = double.tryParse(value);
                              if (price == null || price <= 0) {
                                return 'Please enter a valid price';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _dealPricePerKgController,
                            decoration: const InputDecoration(
                              labelText: 'New R/kg Price (R/kg)',
                              hintText: 'e.g., 69.99',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter deal price per kg';
                              }
                              final price = double.tryParse(value);
                              if (price == null || price < 0) {
                                return 'Please enter a valid price';
                              }
                              if (price >= _pricePerKg) {
                                return 'Deal price must be less than regular price';
                              }
                              return null;
                            },
                          ),
                        ] else if (_selectedType != DiscountType.billDiscount &&
                            _selectedType != DiscountType.buyGet &&
                            _selectedType != DiscountType.percentItem) ...[
                          // Show regular item price for non-weight and non-bill discount types
                          TextFormField(
                            controller: _itemPriceController,
                            decoration: InputDecoration(
                              labelText: _selectedType == DiscountType.onceOff
                                  ? 'Original Price (R)'
                                  : 'Item Price (R)',
                              hintText: 'e.g., 50.00',
                              helperText: _selectedType == DiscountType.onceOff
                                  ? 'The regular/original price before discount'
                                  : null,
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter an item price';
                              }
                              final price = double.tryParse(value);
                              if (price == null || price <= 0) {
                                return 'Please enter a valid price';
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Show percentage field for percentage type
                        if (_selectedType == DiscountType.percentage)
                          TextFormField(
                            controller: _percentageController,
                            decoration: const InputDecoration(
                              labelText: 'Percentage (%)',
                              hintText: 'e.g., 10',
                              helperText:
                                  'Final price after discount must be at least R5.00',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a percentage';
                              }
                              final percent = double.tryParse(value);
                              if (percent == null ||
                                  percent <= 0 ||
                                  percent > 100) {
                                return 'Please enter a valid percentage (1-100)';
                              }
                              // Check if calculated deal price meets minimum
                              final dealPrice =
                                  _itemPrice * (1 - percent / 100);
                              if (dealPrice < 5.00) {
                                return 'Deal price must be at least R5.00 (adjust percentage or item price)';
                              }
                              return null;
                            },
                          ),

                        // Show deal price field for fixed amount type
                        if (_selectedType == DiscountType.fixedAmount)
                          TextFormField(
                            controller: _dealPriceController,
                            decoration: const InputDecoration(
                              labelText: 'Deal Price (R)',
                              hintText: 'e.g., 45.00',
                              helperText:
                                  'Member pays this amount (min R5.00 for payment processing)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a deal price';
                              }
                              final price = double.tryParse(value);
                              if (price == null || price < 0) {
                                return 'Please enter a valid price';
                              }
                              if (price < 5.00) {
                                return 'Minimum R5.00 required for payment processing';
                              }
                              if (price >= _itemPrice) {
                                return 'Deal price must be less than item price';
                              }
                              return null;
                            },
                          ),

                        // Show deal price field for once-off type
                        if (_selectedType == DiscountType.onceOff) ...[
                          TextFormField(
                            controller: _dealPriceController,
                            decoration: const InputDecoration(
                              labelText: 'Member Pays (R)',
                              helperText:
                                  'What the member will actually pay after discount (min R5.00 for payment processing)',
                              hintText: 'e.g., 45.00',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter member price';
                              }
                              final price = double.tryParse(value);
                              if (price == null || price < 0) {
                                return 'Please enter a valid price';
                              }
                              if (price < 5.00) {
                                return 'Minimum R5.00 required for payment processing';
                              }
                              if (price >= _itemPrice) {
                                return 'Member price must be less than item price';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          // Show pricing preview for once-off
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Pricing Preview:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Original Price:',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      'R${_itemPrice.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Member Pays:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green,
                                      ),
                                    ),
                                    Text(
                                      'R${_calculatedDealPrice.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Member Saves:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green,
                                      ),
                                    ),
                                    Text(
                                      'R${_savings.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_calculatedDealPrice < 5.00) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: Colors.red.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.warning,
                                          size: 16,
                                          color: Colors.red.shade700,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Payment processor requires minimum R5.00',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.red.shade700,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],

                        // Image Upload Section - Available for ALL deal types
                        const SizedBox(height: 16),
                        const Text(
                          'Deal Image (Optional)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            children: [
                              if (_selectedImage != null) ...[
                                // BuyGet Deal Preview
                                if (_selectedType == DiscountType.buyGet) ...[
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.green.shade200,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Deal Preview:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Buy: ${_buyItemNameController.text.isEmpty ? 'Item' : _buyItemNameController.text} (R${_buyItemPriceController.text.isEmpty ? '0.00' : _buyItemPriceController.text})',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                        Text(
                                          'Free: ${_freeItemNameController.text.isEmpty ? 'Item' : _freeItemNameController.text} (R${_freeItemPriceController.text.isEmpty ? '0.00' : _freeItemPriceController.text})',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Total:',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                            Text(
                                              'R${_buyItemPriceController.text.isEmpty ? '0.00' : _buyItemPriceController.text}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Savings:',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.green,
                                              ),
                                            ),
                                            Text(
                                              'R${_freeItemPriceController.text.isEmpty ? '0.00' : _freeItemPriceController.text}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                // PercentItem Deal Preview
                                if (_selectedType ==
                                    DiscountType.percentItem) ...[
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.indigo.shade200,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Deal Preview:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.indigo,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Member enters item price',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade700,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Example: R100.00 item',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Discount:',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                            Text(
                                              '${_percentDiscountController.text.isEmpty ? '0' : _percentDiscountController.text}%',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Deal Price:',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                            Text(
                                              'R${_percentDiscountController.text.isEmpty ? '100.00' : (100 * (1 - (double.tryParse(_percentDiscountController.text) ?? 0) / 100)).toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Savings:',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.green,
                                              ),
                                            ),
                                            Text(
                                              'R${_percentDiscountController.text.isEmpty ? '0.00' : (100 * (double.tryParse(_percentDiscountController.text) ?? 0) / 100).toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                              // Show selected image preview or upload button
                              if (_selectedImage != null) ...[
                                // Show newly selected image
                                Container(
                                  height: 150,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    image: DecorationImage(
                                      image: FileImage(File(_selectedImage!.path)),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _selectedImage!.name,
                                        style: const TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: _removeImage,
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      tooltip: 'Remove image',
                                    ),
                                  ],
                                ),
                              ] else ...[
                                // No image - show upload button
                                InkWell(
                                  onTap: _pickImage,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    height: 100,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_photo_alternate,
                                          size: 32,
                                          color: Colors.grey.shade400,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Tap to add deal image',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (_isUploadingImage) ...[
                                const SizedBox(height: 8),
                                const LinearProgressIndicator(),
                                const SizedBox(height: 4),
                                const Text(
                                  'Uploading image...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Schedule section
                        const SizedBox(height: 16),
                        DealScheduleWidget(
                          initialSchedule: _dealSchedule,
                          onScheduleChanged: (schedule) {
                            setState(() {
                              _dealSchedule = schedule;
                            });
                            // Auto-scroll to show schedule fields when toggle is enabled
                            if (schedule != null) {
                              Future.delayed(
                                const Duration(milliseconds: 300),
                                () {
                                  if (_scrollController.hasClients) {
                                    _scrollController.animateTo(
                                      _scrollController
                                          .position
                                          .maxScrollExtent,
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeOut,
                                    );
                                  }
                                },
                              );
                            }
                          },
                        ),

                        // Preview section for free delivery deals
                        if (_selectedType == DiscountType.freeDelivery &&
                            _itemPrice > 0) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Deal Preview (Free Delivery):',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_itemNameController.text.isEmpty ? 'Item' : _itemNameController.text}: R${_itemPrice.toStringAsFixed(2)} + free delivery',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                const Text(
                                  'Item stays at its normal price; the member pays nothing for delivery.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Preview section for regular deals
                        if (_selectedType != DiscountType.weight &&
                            _selectedType != DiscountType.freeDelivery &&
                            _itemPrice > 0 &&
                            _savings > 0) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Deal Preview:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_itemNameController.text.isEmpty ? 'Item' : _itemNameController.text}: R${_itemPrice.toStringAsFixed(2)} → R${_calculatedDealPrice.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                Text(
                                  'You save: R${_savings.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Preview section for weight-based deals
                        if (_selectedType == DiscountType.weight &&
                            _pricePerKg > 0 &&
                            _savingsPerKg > 0) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Deal Preview (Weight-Based):',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_itemNameController.text.isEmpty ? 'Item' : _itemNameController.text}: R${_pricePerKg.toStringAsFixed(2)}/kg → R${_dealPricePerKg.toStringAsFixed(2)}/kg',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                Text(
                                  'Save: R${_savingsPerKg.toStringAsFixed(2)}/kg',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Divider(),
                                const SizedBox(height: 4),
                                const Text(
                                  'Example for 500g:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  'Customer pays: R${((_dealPricePerKg * 500) / 1000).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  'Saves: R${((_savingsPerKg * 500) / 1000).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Action buttons
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _selectedType != DiscountType.none && !_isSubmitting
                        ? _submit
                        : null,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add Deal'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExclusionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Exclusions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (_exclusions.isNotEmpty)
                    Text(
                      '${_exclusions.length} exclusion(s) configured',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: _addExclusion,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_exclusions.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Text(
              'No exclusions added yet. Click "Add" to add items to exclude from the discount.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          )
        else
          ..._exclusions.asMap().entries.map((entry) {
            final index = entry.key;
            final exclusion = entry.value;
            final selectedDays = (exclusion['daysOfWeek'] as List<dynamic>? ?? [])
              .map((day) => day.toString())
              .toList();
            final dayLabel = exclusion['allDays'] == true
              ? 'All days'
              : selectedDays.isNotEmpty
                ? selectedDays.join(', ')
                : exclusion['dayOfWeek'] ?? 'Unknown';
            final isRecurring = exclusion['recurring'] == true;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(exclusion['name'] ?? ''),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Amount: R${exclusion['amount']?.toStringAsFixed(2) ?? '0.00'} each',
                    ),
                    Text(
                      '$dayLabel • ${isRecurring ? 'Recurring (Every week)' : 'Once off'}',
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeExclusion(index),
                ),
              ),
            );
          }),
      ],
    );
  }

  void _addExclusion() {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final selectedDays = <String>{};
    bool allDays = false;
    bool isRecurring = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Exclusion'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Item Name',
                    hintText: 'e.g., Alcohol, Cigarettes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount (R)',
                    hintText: 'e.g., 50.00',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Excluded on',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('All days'),
                  value: allDays,
                  onChanged: (value) {
                    setDialogState(() {
                      allDays = value ?? false;
                      if (allDays) selectedDays.clear();
                    });
                  },
                ),
                if (!allDays)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      'Monday',
                      'Tuesday',
                      'Wednesday',
                      'Thursday',
                      'Friday',
                      'Saturday',
                      'Sunday',
                    ].map((day) {
                      return FilterChip(
                        label: Text(day),
                        selected: selectedDays.contains(day),
                        onSelected: (selected) {
                          setDialogState(() {
                            if (selected) {
                              selectedDays.add(day);
                            } else {
                              selectedDays.remove(day);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Recurring'),
                  subtitle: const Text('Apply this exclusion every week'),
                  value: isRecurring,
                  onChanged: (value) {
                    setDialogState(() => isRecurring = value ?? false);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty &&
                    amountController.text.isNotEmpty &&
                    (allDays || selectedDays.isNotEmpty)) {
                  setState(() {
                    _exclusions.add({
                      'name': nameController.text.trim(),
                      'amount': double.parse(amountController.text),
                      'allDays': allDays,
                      'daysOfWeek': selectedDays.toList(),
                      // Keep the legacy field for existing consumers and
                      // single-day records.
                      'dayOfWeek': selectedDays.length == 1
                          ? selectedDays.first
                          : null,
                      'recurring': isRecurring,
                    });
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _removeExclusion(int index) {
    setState(() {
      _exclusions.removeAt(index);
    });
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        // Read the image bytes for uploading
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedImage = image;
          _imageBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    }
  }

  Future<String?> _uploadImage() async {
    print(
      '🔍 AddDiscountDialog._uploadImage: START - _selectedImage=$_selectedImage',
    );
    if (_selectedImage == null || _imageBytes == null) {
      print(
        '❌ AddDiscountDialog._uploadImage: No image selected, returning null',
      );
      return null;
    }

    print(
      '📸 AddDiscountDialog._uploadImage: Image selected: ${_selectedImage!.name}',
    );
    setState(() {
      _isUploadingImage = true;
    });

    try {
      final fileBytes = _imageBytes!;
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_selectedImage!.name}';
      // Determine target folder for the image. Use trustedPartnerId if provided
      // (used when admins create deals for a partner), otherwise use current
      // user id (trusted partner creating their own deal).
      final targetPartnerId =
          widget.trustedPartnerId ??
          SupabaseService.instance.getCurrentUser()?.id;
        final currentUserId = SupabaseService.instance.getCurrentUser()?.id;

        Future<String> uploadToPath(String path) async {
        await SupabaseService.instance.client.storage
          .from('business-bills')
          .uploadBinary(path, Uint8List.fromList(fileBytes));
        return SupabaseService.instance.client.storage
          .from('business-bills')
          .getPublicUrl(path);
        }

        final primaryFilePath = targetPartnerId != null
          ? 'deal_images/$targetPartnerId/$fileName'
          : 'deal_images/$fileName';

        String imageUrl;
        try {
        imageUrl = await uploadToPath(primaryFilePath);
        } catch (primaryError) {
        // Admin uploads can fail if storage RLS expects uploads under auth.uid().
        final isAdminDealUpload =
          widget.trustedPartnerId != null &&
          currentUserId != null &&
          currentUserId != targetPartnerId;
        if (!isAdminDealUpload) rethrow;

        final fallbackFilePath = 'deal_images/$currentUserId/$fileName';
        print(
          '⚠️ AddDiscountDialog._uploadImage: Primary upload failed ($primaryError). Retrying with admin-owned path: $fallbackFilePath',
        );
        imageUrl = await uploadToPath(fallbackFilePath);
        }

      print('DEBUG: Image uploaded successfully, public URL: $imageUrl');
      print('✅ AddDiscountDialog._uploadImage: Returning imageUrl=$imageUrl');
      return imageUrl;
    } catch (e) {
      print('❌ AddDiscountDialog._uploadImage: Exception: $e');
      if (mounted) {
        // Provide a clearer message for RLS / unauthorized errors.
        final errText = e.toString();
        final friendlyMessage =
            errText.contains('row-level security') || errText.contains('403')
            ? 'Failed to upload image: You are not authorized to upload images for this business. Check that the partner has allowed admin deal creation.'
            : 'Failed to upload image: $errText';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyMessage)));
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
      _imageBytes = null;
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    // Enable autovalidation after first submit attempt
    setState(() {
      _autovalidateMode = AutovalidateMode.onUserInteraction;
    });

    if (_formKey.currentState!.validate()) {
      // Validate that we have a trustedPartnerId
      if (widget.trustedPartnerId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: No trusted partner ID found. Please log in again.'),
            ),
          );
          setState(() {
            _isSubmitting = false;
          });
        }
        return;
      }

      // Upload image if selected
      String? imageUrl;
      print('🎯 AddDiscountDialog._submit: _selectedImage=$_selectedImage');
      if (_selectedImage != null) {
        print('📤 AddDiscountDialog._submit: Calling _uploadImage...');
        imageUrl = await _uploadImage();
        print('📥 AddDiscountDialog._submit: _uploadImage returned: $imageUrl');
      } else {
        print('⚠️ AddDiscountDialog._submit: No image selected');
      }

      double itemPrice = 0.0;
      double percentage = 0.0;
      double? fixedAmount;
      final bool isOnceOff = _isOnceOff || _selectedType == DiscountType.onceOff;
      bool isBillDiscount = false;
      String dealType = 'standard';
      Map<String, dynamic>? customData;
      bool requiresManualPrice = false;
      Map<String, dynamic>? billDiscountData;

      if (_selectedType == DiscountType.percentage) {
        itemPrice = double.tryParse(_itemPriceController.text) ?? 0.0;
        percentage = double.tryParse(_percentageController.text) ?? 0.0;
      } else if (_selectedType == DiscountType.fixedAmount) {
        itemPrice = double.tryParse(_itemPriceController.text) ?? 0.0;
        final dealPrice = double.tryParse(_dealPriceController.text) ?? 0.0;
        fixedAmount = itemPrice - dealPrice;
      } else if (_selectedType == DiscountType.onceOff) {
        itemPrice = double.tryParse(_itemPriceController.text) ?? 0.0;
        final dealPrice = double.tryParse(_dealPriceController.text) ?? 0.0;
        fixedAmount = itemPrice - dealPrice;
      } else if (_selectedType == DiscountType.weight) {
        // For weight-based deals, store price per kg as item price
        dealType = 'weight';
        itemPrice = double.tryParse(_pricePerKgController.text) ?? 0.0;
        final dealPricePerKg =
            double.tryParse(_dealPricePerKgController.text) ?? 0.0;
        fixedAmount = itemPrice - dealPricePerKg;
      } else if (_selectedType == DiscountType.buyGet) {
        dealType = 'buy_get';
        final buyPrice = double.tryParse(_buyItemPriceController.text) ?? 0.0;
        final freeValue = double.tryParse(_freeItemPriceController.text) ?? 0.0;
        final totalPrice = buyPrice;

        customData = {
          'buy_item_name': _buyItemNameController.text.trim(),
          'buy_item_price': buyPrice,
          'free_item_name': _freeItemNameController.text.trim(),
          'free_item_value': freeValue,
          'total_price': totalPrice,
        };
        itemPrice = totalPrice;
      } else if (_selectedType == DiscountType.percentItem) {
        dealType = 'percent_item';
        requiresManualPrice = true;
        percentage = double.tryParse(_percentDiscountController.text) ?? 0.0;
        itemPrice = 0.0; // Will be entered by member
      } else if (_selectedType == DiscountType.freeDelivery) {
        // No price reduction — the delivery itself is the benefit.
        dealType = 'free_delivery';
        itemPrice = double.tryParse(_itemPriceController.text) ?? 0.0;
        percentage = 0.0;
      } else if (_selectedType == DiscountType.billDiscount) {
        isBillDiscount = true;
        billDiscountData = {
          'isPercentage': _billDiscountIsPercentage,
          'percentage': _billDiscountIsPercentage
              ? (double.tryParse(_billDiscountPercentageController.text) ?? 0.0)
              : 0.0,
          'totalDiscount': !_billDiscountIsPercentage
              ? (double.tryParse(_billDiscountTotalController.text) ?? 0.0)
              : 0.0,
          'exclusions': _exclusions,
        };
        // For bill discount, we'll use percentage or fixed amount to store the discount
        if (_billDiscountIsPercentage) {
          percentage =
              double.tryParse(_billDiscountPercentageController.text) ?? 0.0;
        } else {
          fixedAmount =
              double.tryParse(_billDiscountTotalController.text) ?? 0.0;
        }
      }

      final result = {
        'trustedPartnerId': widget.trustedPartnerId,
        'name': _descriptionController.text.trim(),
        'description': _descriptionController.text.trim(),
        'itemName': _selectedType == DiscountType.billDiscount
            ? 'Bill Discount'
            : (_selectedType == DiscountType.buyGet
                  ? '${_buyItemNameController.text.trim()} + ${_freeItemNameController.text.trim()}'
                  : _itemNameController.text.trim()),
        'itemPrice': itemPrice,
        'percentage': percentage,
        'fixedAmount': fixedAmount,
        'isWeightBased': _selectedType == DiscountType.weight,
        'isBillDiscount': isBillDiscount,
        'isOnceOff': isOnceOff,
        'billDiscountData': billDiscountData,
        'imageUrl': imageUrl,
        'scheduleData': _dealSchedule?.toJson(),
        'dealCategory': _selectedCategory,
        'offersDelivery':
            _offersDelivery || _selectedType == DiscountType.freeDelivery,
        'dealType': dealType,
        'customData': customData,
        'requiresManualPrice': requiresManualPrice,
      };
      print('🔹 AddDiscountDialog result map: imageUrl=${result['imageUrl']}');
      Navigator.of(context).pop(result);
      print('🔹 AddDiscountDialog popped with result');
    }

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
    }
  }
}

// Edit Discount Dialog
class EditDiscountDialog extends StatefulWidget {
  final Discount discount;
  final String? trustedPartnerId;
  final String? lockedDealCategory;

  const EditDiscountDialog({
    super.key,
    required this.discount,
    this.trustedPartnerId,
    this.lockedDealCategory,
  });

  @override
  State<EditDiscountDialog> createState() => _EditDiscountDialogState();
}

class _EditDiscountDialogState extends State<EditDiscountDialog> {
  final Logger _logger = Logger();
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _descriptionController = TextEditingController();
  final _itemNameController = TextEditingController();
  final _itemPriceController = TextEditingController();
  final _percentageController = TextEditingController();
  final _dealPriceController = TextEditingController();
  final _pricePerKgController = TextEditingController();
  final _dealPricePerKgController = TextEditingController();

  // Bill discount controllers
  final _billDiscountPercentageController = TextEditingController();
  final _billDiscountTotalController = TextEditingController();

  // Buy-Get & Percent-Item specific controllers
  final _buyItemNameController = TextEditingController();
  final _buyItemPriceController = TextEditingController();
  final _freeItemNameController = TextEditingController();
  final _freeItemPriceController = TextEditingController();
  final _percentDiscountController = TextEditingController();

  late DiscountType _selectedType;
  bool _isOnceOff = false;
  late String _selectedCategory; // Deal category for edit
  late bool _offersDelivery;
  double _itemPrice = 0.0;
  double _calculatedDealPrice = 0.0;
  double _savings = 0.0;
  double _pricePerKg = 0.0;
  double _dealPricePerKg = 0.0;
  double _savingsPerKg = 0.0;

  // Bill discount state
  bool _billDiscountIsPercentage = true;
  List<Map<String, dynamic>> _exclusions = [];

  // Image upload state
  XFile? _selectedImage;
  List<int>? _imageBytes;
  bool _isUploadingImage = false;
  String? _existingImageUrl; // Track existing image from database
  bool _shouldDeleteExistingImage = false; // Flag to delete existing image

  // Schedule state
  DealSchedule? _dealSchedule;

  @override
  void initState() {
    super.initState();

    // Store existing image URL
    _existingImageUrl = widget.discount.imageUrl;

    // Initialize category from existing discount
    _selectedCategory =
      widget.lockedDealCategory ?? widget.discount.dealCategory;
    _offersDelivery = widget.discount.offersDelivery;
    _isOnceOff = widget.discount.isOnceOff;

    // Load existing schedule data if available
    if (widget.discount.scheduleData != null) {
      _dealSchedule = DealSchedule.fromJson(widget.discount.scheduleData!);
    }

    // Determine discount type from existing discount
    if (widget.discount.dealType == 'buyGet' ||
        widget.discount.dealType == 'buy_get') {
      _selectedType = DiscountType.buyGet;
      if (widget.discount.customData != null) {
        _buyItemNameController.text =
            widget.discount.customData!['buy_item_name'] ?? '';
        _buyItemPriceController.text =
            (widget.discount.customData!['buy_item_price'] ?? 0).toString();
        _freeItemNameController.text =
            widget.discount.customData!['free_item_name'] ?? '';
        _freeItemPriceController.text =
            (widget.discount.customData!['free_item_value'] ?? 0).toString();
      }
    } else if (widget.discount.dealType == 'percentItem' ||
        widget.discount.dealType == 'percent_item') {
      _selectedType = DiscountType.percentItem;
      // For percentItem, the percentage is stored in the main percentage field
      _percentDiscountController.text = widget.discount.percentage.toString();
    } else if (widget.discount.isFreeDelivery) {
      _selectedType = DiscountType.freeDelivery;
    } else if (widget.discount.isBillDiscount) {
      _selectedType = DiscountType.billDiscount;
      // Pre-fill bill discount data
      if (widget.discount.billDiscountData != null) {
        _billDiscountIsPercentage =
            widget.discount.billDiscountData!['isPercentage'] ?? true;
        if (_billDiscountIsPercentage) {
          _billDiscountPercentageController.text =
              (widget.discount.billDiscountData!['percentage'] ??
                      widget.discount.percentage)
                  .toString();
        } else {
          _billDiscountTotalController.text =
              (widget.discount.billDiscountData!['totalDiscount'] ??
                      widget.discount.fixedAmount ??
                      0)
                  .toString();
        }
        _exclusions = List<Map<String, dynamic>>.from(
          widget.discount.billDiscountData!['exclusions'] ?? [],
        );
      }
    } else if (widget.discount.isWeightBased) {
      _selectedType = DiscountType.weight;
      _pricePerKgController.text = widget.discount.itemPrice.toString();
      _dealPricePerKgController.text = widget.discount.dealPrice.toString();
    } else if (widget.discount.isOnceOff) {
      _selectedType = DiscountType.onceOff;
      _itemPriceController.text = widget.discount.itemPrice.toString();
      _dealPriceController.text = widget.discount.dealPrice.toString();
    } else if (widget.discount.percentage > 0) {
      _selectedType = DiscountType.percentage;
      _itemPriceController.text = widget.discount.itemPrice.toString();
      _percentageController.text = widget.discount.percentage.toString();
    } else {
      _selectedType = DiscountType.fixedAmount;
      _itemPriceController.text = widget.discount.itemPrice.toString();
      _dealPriceController.text = widget.discount.dealPrice.toString();
    }

    // Pre-fill common fields
    _descriptionController.text = widget.discount.description;
    _itemNameController.text = widget.discount.itemName;

    _itemPriceController.addListener(_calculateValues);
    _percentageController.addListener(_calculateValues);
    _dealPriceController.addListener(_calculateValues);
    _pricePerKgController.addListener(_calculateValues);
    _dealPricePerKgController.addListener(_calculateValues);

    // Trigger initial calculation
    _calculateValues();
  }

  // Helper to handle existing image deletion
  void _handleDeleteExistingImage() {
    setState(() {
      if (_existingImageUrl != null) {
        _shouldDeleteExistingImage = true;
        _existingImageUrl = null;
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _descriptionController.dispose();
    _itemNameController.dispose();
    _itemPriceController.dispose();
    _percentageController.dispose();
    _dealPriceController.dispose();
    _pricePerKgController.dispose();
    _dealPricePerKgController.dispose();
    _billDiscountPercentageController.dispose();
    _billDiscountTotalController.dispose();
    _buyItemNameController.dispose();
    _buyItemPriceController.dispose();
    _freeItemNameController.dispose();
    _freeItemPriceController.dispose();
    _percentDiscountController.dispose();
    super.dispose();
  }

  void _calculateValues() {
    final itemPrice = double.tryParse(_itemPriceController.text) ?? 0.0;
    setState(() {
      _itemPrice = itemPrice;

      if (_selectedType == DiscountType.percentage) {
        final percentage = double.tryParse(_percentageController.text) ?? 0.0;
        _calculatedDealPrice = itemPrice * (1 - percentage / 100);
        _savings = itemPrice - _calculatedDealPrice;
      } else if (_selectedType == DiscountType.fixedAmount ||
          _selectedType == DiscountType.onceOff) {
        final dealPrice = double.tryParse(_dealPriceController.text) ?? 0.0;
        _calculatedDealPrice = dealPrice;
        _savings = itemPrice - dealPrice;
      } else if (_selectedType == DiscountType.weight) {
        final pricePerKg = double.tryParse(_pricePerKgController.text) ?? 0.0;
        final dealPricePerKg =
            double.tryParse(_dealPricePerKgController.text) ?? 0.0;
        _pricePerKg = pricePerKg;
        _dealPricePerKg = dealPricePerKg;
        _savingsPerKg = pricePerKg - dealPricePerKg;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Deal'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          controller: _scrollController,
          // Top inset stops the first field's floating label being clipped.
          padding: const EdgeInsets.only(top: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Dropdown for discount type - READ ONLY (shows current type)
                DropdownButtonFormField<DiscountType>(
                  isExpanded: true,
                  initialValue: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Discount Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: DiscountType.percentage,
                      child: Text('Percentage'),
                    ),
                    DropdownMenuItem(
                      value: DiscountType.fixedAmount,
                      child: Text('Fixed Amount'),
                    ),
                    DropdownMenuItem(
                      value: DiscountType.onceOff,
                      child: Text('Once-Off Deal'),
                    ),
                    DropdownMenuItem(
                      value: DiscountType.weight,
                      child: Text('Weight'),
                    ),
                    DropdownMenuItem(
                      value: DiscountType.billDiscount,
                      child: Text('Bill Discount'),
                    ),
                    DropdownMenuItem(
                      value: DiscountType.buyGet,
                      child: Text('Buy This Get That'),
                    ),
                    DropdownMenuItem(
                      value: DiscountType.percentItem,
                      child: Text('% Off Item (Manual Price)'),
                    ),
                    DropdownMenuItem(
                      value: DiscountType.freeDelivery,
                      child: Text('Free Delivery (normal price)'),
                    ),
                  ],
                  onChanged: null, // Disabled - cannot change type
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Once-off deal'),
                  subtitle: const Text(
                    'Each member can successfully use this deal only once.',
                  ),
                  value: _isOnceOff,
                  onChanged: (value) => setState(() {
                    _isOnceOff = value ?? false;
                  }),
                ),

                // Deal Category is fixed for Fresh & Local and Local Sips partners.
                const SizedBox(height: 16),
                if (widget.lockedDealCategory != null)
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Deal Category',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      widget.lockedDealCategory!,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Deal Category',
                      hintText: 'Select a category for this deal',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final category in kDealCategories)
                        _buildCategoryMenuItem(category),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = value ?? 'Other';
                      });
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please select a category';
                      }
                      return null;
                    },
                  ),
                LiquorLicenceWarning(selectedCategory: _selectedCategory),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _offersDelivery,
                  title: const Text('Delivery available'),
                  subtitle: const Text(
                    'Members will see a delivery note on this deal',
                  ),
                  secondary: const Icon(Icons.delivery_dining),
                  onChanged: (value) =>
                      setState(() => _offersDelivery = value),
                ),

                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Deal Description',
                    hintText: 'e.g., Weekend Special, Student Deal',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a deal description';
                    }
                    return null;
                  },
                ),

                // Bill Discount specific fields
                if (_selectedType == DiscountType.billDiscount) ...[
                  const SizedBox(height: 16),
                  // Percentage/Total Toggle
                  Row(
                    children: [
                      const Text(
                        'Discount Type:',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: true,
                              label: Text('Percentage'),
                            ),
                            ButtonSegment(value: false, label: Text('Total')),
                          ],
                          selected: {_billDiscountIsPercentage},
                          onSelectionChanged: (Set<bool> selected) {
                            setState(
                              () => _billDiscountIsPercentage = selected.first,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Show percentage or total field based on toggle
                  if (_billDiscountIsPercentage)
                    TextFormField(
                      controller: _billDiscountPercentageController,
                      decoration: const InputDecoration(
                        labelText: 'Discount Percentage (%)',
                        hintText: 'e.g., 10',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a percentage';
                        }
                        final percent = double.tryParse(value);
                        if (percent == null || percent <= 0 || percent > 100) {
                          return 'Please enter a valid percentage (1-100)';
                        }
                        return null;
                      },
                    )
                  else
                    TextFormField(
                      controller: _billDiscountTotalController,
                      decoration: const InputDecoration(
                        labelText: 'Fixed Discount Amount (R)',
                        hintText: 'e.g., 50.00',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a discount amount';
                        }
                        final amount = double.tryParse(value);
                        if (amount == null || amount <= 0) {
                          return 'Please enter a valid amount';
                        }
                        return null;
                      },
                    ),
                ],

                const SizedBox(height: 16),

                // Show item name and pricing fields for non-bill discount types
                if (_selectedType != DiscountType.billDiscount &&
                    _selectedType != DiscountType.buyGet &&
                    _selectedType != DiscountType.percentItem) ...[
                  TextFormField(
                    controller: _itemNameController,
                    decoration: InputDecoration(
                      labelText: 'Item Name',
                      hintText: _selectedType == DiscountType.weight
                          ? 'e.g., Apples, Tomatoes, Chicken'
                          : 'e.g., Coffee, Burger, Pizza',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter an item name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // BUY-GET DEAL FIELDS
                if (_selectedType == DiscountType.buyGet) ...[
                  const Text(
                    'Buy Item',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _buyItemNameController,
                    decoration: const InputDecoration(
                      labelText: 'Item Name (what member buys)',
                      hintText: 'e.g., Coffee',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter item name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _buyItemPriceController,
                    decoration: const InputDecoration(
                      labelText: 'Normal Price (R)',
                      hintText: 'e.g., 75.00',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter price';
                      }
                      final price = double.tryParse(value);
                      if (price == null || price <= 0) {
                        return 'Enter valid price';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Free Item',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _freeItemNameController,
                    decoration: const InputDecoration(
                      labelText: 'Item Name (what member gets free)',
                      hintText: 'e.g., Pastry',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter free item name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _freeItemPriceController,
                    decoration: const InputDecoration(
                      labelText: 'Normally Costs (R)',
                      hintText: 'e.g., 45.00',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter free item value';
                      }
                      final price = double.tryParse(value);
                      if (price == null || price <= 0) {
                        return 'Enter valid price';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                // PERCENT-ITEM DEAL FIELDS
                if (_selectedType == DiscountType.percentItem) ...[
                  const Text(
                    'Member will enter the item price when requesting. Discount will be applied as a percentage off that price.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _percentDiscountController,
                    decoration: const InputDecoration(
                      labelText: 'Discount Percentage (%)',
                      hintText: 'e.g., 15',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter percentage';
                      }
                      final percent = double.tryParse(value);
                      if (percent == null || percent <= 0 || percent > 100) {
                        return 'Enter valid percentage (1-100)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                // Show weight-based fields for weight type
                if (_selectedType == DiscountType.weight) ...[
                  TextFormField(
                    controller: _pricePerKgController,
                    decoration: const InputDecoration(
                      labelText: 'R/kg Price (R/kg)',
                      hintText: 'e.g., 89.99',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter price per kg';
                      }
                      final price = double.tryParse(value);
                      if (price == null || price <= 0) {
                        return 'Please enter a valid price';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _dealPricePerKgController,
                    decoration: const InputDecoration(
                      labelText: 'New R/kg Price (R/kg)',
                      hintText: 'e.g., 69.99',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter deal price per kg';
                      }
                      final price = double.tryParse(value);
                      if (price == null || price < 0) {
                        return 'Please enter a valid price';
                      }
                      if (price >= _pricePerKg) {
                        return 'Deal price must be less than regular price';
                      }
                      return null;
                    },
                  ),
                ] else if (_selectedType != DiscountType.billDiscount &&
                    _selectedType != DiscountType.buyGet &&
                    _selectedType != DiscountType.percentItem) ...[
                  // Show regular item price for non-weight and non-bill discount types
                  TextFormField(
                    controller: _itemPriceController,
                    decoration: InputDecoration(
                      labelText: _selectedType == DiscountType.onceOff
                          ? 'Original Price (R)'
                          : 'Item Price (R)',
                      hintText: 'e.g., 50.00',
                      helperText: _selectedType == DiscountType.onceOff
                          ? 'The regular/original price before discount'
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter an item price';
                      }
                      final price = double.tryParse(value);
                      if (price == null || price <= 0) {
                        return 'Please enter a valid price';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 16),

                // Show percentage field for percentage type
                if (_selectedType == DiscountType.percentage)
                  TextFormField(
                    controller: _percentageController,
                    decoration: const InputDecoration(
                      labelText: 'Percentage (%)',
                      hintText: 'e.g., 10',
                      helperText:
                          'Final price after discount must be at least R5.00',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a percentage';
                      }
                      final percent = double.tryParse(value);
                      if (percent == null || percent <= 0 || percent > 100) {
                        return 'Please enter a valid percentage (1-100)';
                      }
                      // Check if calculated deal price meets minimum
                      final dealPrice = _itemPrice * (1 - percent / 100);
                      if (dealPrice < 5.00) {
                        return 'Deal price must be at least R5.00 (adjust percentage or item price)';
                      }
                      return null;
                    },
                  ),

                // Show deal price field for fixed amount type
                if (_selectedType == DiscountType.fixedAmount)
                  TextFormField(
                    controller: _dealPriceController,
                    decoration: const InputDecoration(
                      labelText: 'Deal Price (R)',
                      hintText: 'e.g., 45.00',
                      helperText:
                          'Member pays this amount (min R5.00 for payment processing)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a deal price';
                      }
                      final price = double.tryParse(value);
                      if (price == null || price < 0) {
                        return 'Please enter a valid price';
                      }
                      if (price < 5.00) {
                        return 'Minimum R5.00 required for payment processing';
                      }
                      if (price >= _itemPrice) {
                        return 'Deal price must be less than item price';
                      }
                      return null;
                    },
                  ),

                // Show deal price field for once-off type
                if (_selectedType == DiscountType.onceOff) ...[
                  TextFormField(
                    controller: _dealPriceController,
                    decoration: const InputDecoration(
                      labelText: 'Member Pays (R)',
                      helperText:
                          'What the member will actually pay after discount (min R5.00 for payment processing)',
                      hintText: 'e.g., 45.00',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter member price';
                      }
                      final price = double.tryParse(value);
                      if (price == null || price < 0) {
                        return 'Please enter a valid price';
                      }
                      if (price < 5.00) {
                        return 'Minimum R5.00 required for payment processing';
                      }
                      if (price >= _itemPrice) {
                        return 'Member price must be less than item price';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  // Show pricing preview for once-off
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pricing Preview:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Original Price:',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(
                              'R${_itemPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Member Pays:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              'R${_calculatedDealPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Member Saves:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              'R${_savings.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        if (_calculatedDealPrice < 5.00) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.red.shade300),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning,
                                  size: 16,
                                  color: Colors.red.shade700,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Payment processor requires minimum R5.00',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // Image Upload Section - Available for ALL deal types
                const SizedBox(height: 16),
                const Text(
                  'Deal Image (Optional)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      if (_selectedImage != null) ...[
                        // Show newly selected image
                        Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(
                              image: FileImage(File(_selectedImage!.path)),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectedImage!.name,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              onPressed: _removeImage,
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Remove image',
                            ),
                          ],
                        ),
                      ] else if (_existingImageUrl != null &&
                          _existingImageUrl!.isNotEmpty) ...[
                        // Show existing image from database
                        Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _existingImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: Icon(
                                      Icons.broken_image,
                                      color: Colors.grey,
                                      size: 48,
                                    ),
                                  ),
                                );
                              },
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      color: Colors.grey.shade200,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          value:
                                              loadingProgress
                                                      .expectedTotalBytes !=
                                                  null
                                              ? loadingProgress
                                                        .cumulativeBytesLoaded /
                                                    loadingProgress
                                                        .expectedTotalBytes!
                                              : null,
                                        ),
                                      ),
                                    );
                                  },
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Current deal image',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              onPressed: _removeImage,
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Remove image',
                            ),
                          ],
                        ),
                      ] else ...[
                        // No image - show upload button
                        InkWell(
                          onTap: _pickImage,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 100,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate,
                                  size: 32,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap to add deal image',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_isUploadingImage) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 4),
                        const Text(
                          'Uploading image...',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Schedule section
                DealScheduleWidget(
                  initialSchedule: _dealSchedule,
                  onScheduleChanged: (schedule) {
                    setState(() {
                      _dealSchedule = schedule;
                    });
                    // Auto-scroll to show schedule fields when toggle is enabled
                    if (schedule != null) {
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (_scrollController.hasClients) {
                          _scrollController.animateTo(
                            _scrollController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Preview section for regular deals
                if (_selectedType != DiscountType.weight &&
                    _selectedType != DiscountType.billDiscount &&
                    _itemPrice > 0 &&
                    _savings > 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Deal Preview:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_itemNameController.text.isEmpty ? 'Item' : _itemNameController.text}: R${_itemPrice.toStringAsFixed(2)} → R${_calculatedDealPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        Text(
                          'You save: R${_savings.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Preview section for weight-based deals
                if (_selectedType == DiscountType.weight &&
                    _pricePerKg > 0 &&
                    _savingsPerKg > 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Deal Preview (Weight-Based):',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_itemNameController.text.isEmpty ? 'Item' : _itemNameController.text}: R${_pricePerKg.toStringAsFixed(2)}/kg → R${_dealPricePerKg.toStringAsFixed(2)}/kg',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        Text(
                          'Save: R${_savingsPerKg.toStringAsFixed(2)}/kg',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 4),
                        const Text(
                          'Example for 500g:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          'Customer pays: R${((_dealPricePerKg * 500) / 1000).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          'Saves: R${((_savingsPerKg * 500) / 1000).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _deleteDeal,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Delete Deal'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Update Deal')),
      ],
    );
  }

  // Note: Duplicate _addExclusion and _removeExclusion methods removed
  // The active implementations are defined earlier in the file around lines 934-1040

  Future<void> _deleteDeal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Deal'),
        content: const Text(
          'Are you sure you want to delete this deal? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await SupabaseService.instance.client
            .from('trusted_partner_discounts')
            .delete()
            .eq('id', widget.discount.id);

        if (mounted) {
          Navigator.of(context).pop({'deleted': true});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Deal deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete deal: $e')));
        }
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        // Read bytes immediately to prevent path errors on Android
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedImage = image;
          _imageBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null || _imageBytes == null) return null;

    setState(() {
      _isUploadingImage = true;
    });

    try {
      final fileBytes = _imageBytes!;
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_selectedImage!.name}';
      final targetPartnerId =
          widget.trustedPartnerId ??
          SupabaseService.instance.getCurrentUser()?.id;
      final currentUserId = SupabaseService.instance.getCurrentUser()?.id;

      Future<String> uploadToPath(String path) async {
        await SupabaseService.instance.client.storage
            .from('business-bills')
            .uploadBinary(path, Uint8List.fromList(fileBytes));
        return SupabaseService.instance.client.storage
            .from('business-bills')
            .getPublicUrl(path);
      }

      final primaryFilePath = targetPartnerId != null
          ? 'deal_images/$targetPartnerId/$fileName'
          : 'deal_images/$fileName';

      _logger.i(
        'Uploading image - Path: $primaryFilePath, Partner: $targetPartnerId, IsAdminUpload: ${widget.trustedPartnerId != null}',
      );

      String imageUrl;
      try {
        imageUrl = await uploadToPath(primaryFilePath);
      } catch (primaryError) {
        // Admin uploads can fail if storage RLS expects uploads under auth.uid().
        final isAdminDealUpload =
            widget.trustedPartnerId != null &&
            currentUserId != null &&
            currentUserId != targetPartnerId;
        if (!isAdminDealUpload) rethrow;

        final fallbackFilePath = 'deal_images/$currentUserId/$fileName';
        _logger.w(
          'Primary upload failed ($primaryError). Retrying with admin-owned path: $fallbackFilePath',
        );
        imageUrl = await uploadToPath(fallbackFilePath);
      }

      _logger.i('Image uploaded successfully, public URL: $imageUrl');
      return imageUrl;
    } catch (e) {
      _logger.e('Upload error: $e (Type: ${e.runtimeType})');
      if (mounted) {
        final errText = e.toString();
        final friendlyMessage =
            errText.contains('row-level security') || errText.contains('403')
            ? 'Failed to upload image: You are not authorized to upload images for this business. Check that the partner has allowed admin deal creation.'
            : 'Failed to upload image: $errText';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyMessage)));
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  void _removeImage() {
    setState(() {
      if (_selectedImage != null) {
        _selectedImage = null;
        _imageBytes = null;
      } else if (_existingImageUrl != null) {
        _handleDeleteExistingImage();
      }
    });
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      // Handle image: new upload, keep existing, or delete
      String? imageUrl = widget.discount.imageUrl; // Default to existing

      if (_selectedImage != null) {
        // New image selected - upload it
        imageUrl = await _uploadImage();
      } else if (_shouldDeleteExistingImage) {
        // User deleted existing image
        imageUrl = null;
      }
      // else: keep existing imageUrl as is

      double itemPrice = 0.0;
      double percentage = 0.0;
      double? fixedAmount;
      final bool isOnceOff = _isOnceOff;
      bool isBillDiscount = false;
      Map<String, dynamic>? billDiscountData;

      if (_selectedType == DiscountType.percentage) {
        itemPrice = double.parse(_itemPriceController.text);
        percentage = double.parse(_percentageController.text);
      } else if (_selectedType == DiscountType.fixedAmount) {
        itemPrice = double.parse(_itemPriceController.text);
      } else if (_selectedType == DiscountType.onceOff) {
        itemPrice = double.parse(_itemPriceController.text);
        final dealPrice = double.parse(_dealPriceController.text);
        fixedAmount = itemPrice - dealPrice;
        fixedAmount = itemPrice - dealPrice;
      } else if (_selectedType == DiscountType.weight) {
        // For weight-based deals, store price per kg as item price
        itemPrice = double.parse(_pricePerKgController.text);
        final dealPricePerKg = double.parse(_dealPricePerKgController.text);
        fixedAmount = itemPrice - dealPricePerKg;
      } else if (_selectedType == DiscountType.freeDelivery) {
        // No price reduction — the delivery itself is the benefit.
        itemPrice = double.parse(_itemPriceController.text);
        percentage = 0.0;
      } else if (_selectedType == DiscountType.billDiscount) {
        isBillDiscount = true;
        billDiscountData = {
          'isPercentage': _billDiscountIsPercentage,
          'percentage': _billDiscountIsPercentage
              ? double.parse(_billDiscountPercentageController.text)
              : 0.0,
          'totalDiscount': !_billDiscountIsPercentage
              ? double.parse(_billDiscountTotalController.text)
              : 0.0,
          'exclusions': _exclusions,
        };
        // For bill discount, we'll use percentage or fixed amount to store the discount
        if (_billDiscountIsPercentage) {
          percentage = double.parse(_billDiscountPercentageController.text);
        } else {
          fixedAmount = double.parse(_billDiscountTotalController.text);
        }
      }

      Map<String, dynamic>? customData;
      if (_selectedType == DiscountType.buyGet) {
        final buyPrice = double.tryParse(_buyItemPriceController.text) ?? 0.0;
        final freeValue = double.tryParse(_freeItemPriceController.text) ?? 0.0;
        itemPrice = buyPrice;
        fixedAmount = freeValue;
        customData = {
          'buy_item_name': _buyItemNameController.text.trim(),
          'buy_item_price': buyPrice,
          'free_item_name': _freeItemNameController.text.trim(),
          'free_item_value': freeValue,
        };
      } else if (_selectedType == DiscountType.percentItem) {
        final percentDiscount =
            double.tryParse(_percentDiscountController.text) ?? 0.0;
        percentage = percentDiscount;
        customData = {'percent_discount': percentDiscount};
      }

      final result = {
        'name': _descriptionController.text.trim(),
        'description': _descriptionController.text.trim(),
        'itemName': _selectedType == DiscountType.billDiscount
            ? 'Bill Discount'
            : (_selectedType == DiscountType.buyGet
                  ? '${_buyItemNameController.text.trim()} + ${_freeItemNameController.text.trim()}'
                  : _itemNameController.text.trim()),
        'itemPrice': itemPrice,
        'percentage': percentage,
        'fixedAmount': fixedAmount,
        'isWeightBased': _selectedType == DiscountType.weight,
        'isBillDiscount': isBillDiscount,
        'isOnceOff': isOnceOff,
        'requiresManualPrice': _selectedType == DiscountType.percentItem,
        'billDiscountData': billDiscountData,
        'imageUrl': imageUrl,
        'scheduleData': _dealSchedule?.toJson(),
        'dealCategory': _selectedCategory,
        'offersDelivery':
            _offersDelivery || _selectedType == DiscountType.freeDelivery,
        'customData': customData,
        'dealType': _selectedType == DiscountType.buyGet
            ? 'buy_get'
            : (_selectedType == DiscountType.percentItem
                  ? 'percent_item'
                  : (_selectedType == DiscountType.freeDelivery
                        ? 'free_delivery'
                        : null)),
      };
      Navigator.of(context).pop(result);
    }
  }
}
