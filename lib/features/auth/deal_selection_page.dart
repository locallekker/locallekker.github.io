import 'dart:async';
import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/deal_categories.dart';
import '../../models/discount.dart';
import '../../models/deal_schedule.dart';
import '../../models/restaurant_deal.dart';
import '../../widgets/restaurant_deal_badge.dart';
import '../members/restaurant_deal_request_page.dart';
import '../business/restaurant_deal_dialog.dart';
import '../../services/discount_service.dart';
import '../../services/supabase_service.dart';
import '../../services/admin_engagement_service.dart';
import '../../services/in_app_payment_availability_service.dart';
import '../../widgets/deal_image_preview.dart';
import '../../widgets/website_redirect_overlay.dart';
import '../admin/website_redirect_deal_dialog.dart';
import '../admin/booking_redirect_deal_dialog.dart';
import 'deal_authorization_request_page.dart';
import 'discount_management_page.dart';

class DealSelectionPage extends StatefulWidget {
  final bool isAdminMode;
  final String? cityFilter;

  const DealSelectionPage({
    super.key,
    this.isAdminMode = false,
    this.cityFilter,
  });

  @override
  State<DealSelectionPage> createState() => _DealSelectionPageState();
}

class _DealSelectionPageState extends State<DealSelectionPage> {
  // Brand colors
  // Pantone 340 C — primary action / "Request" button & header
  static const Color _kBrandGreen = Color(0xFF3C8C44);
  // 50% lighter shade of the brand green — secondary green accents
  static const Color _kAccentGreen = Color(0xFF7FBBA4);
  // Brand blue — partner/category accents (was _kBrandBlue / AppColors.primary)
  static const Color _kBrandBlue = Color(0xFF0E5BA0);

  final DiscountService _discountService = DiscountService();
  Map<String, List<Map<String, dynamic>>> _dealsByPartner = {};
  final Map<String, bool> _expandedPartners =
      {}; // Track which partners are expanded
  bool _isLoading = true;
  final Map<String, int> _quantities =
      {}; // Track quantity for each deal (items or grams)
  String _searchQuery = '';
  Map<String, List<Map<String, dynamic>>> _filteredDealsByPartner = {};

  // Toggle and filter state
  bool _showTrustedPartners = true; // true = Trusted Partners, false = Deals

  // Deal Category Filter (for Partners mode - matches Deals categories)
  String? _selectedPartnerDealCategory; // null = all categories

  // Deal Category Filter (for Deals mode)
  String? _selectedDealCategory; // null = all deal categories
  final List<String> _availableDealCategories = kDealCategories;

  // Deal Type Filter (for Deals mode)
  String? _selectedDealType; // null = all deal types
  List<String> _availableDealTypes = [];
  List<Map<String, dynamic>> _allDeals = []; // Flat list of all deals

  // City filter
  String? _selectedCityFilter;
  List<String> _availableCities = [];

  String _displayDealImageUrl(String url) {
    // Extract timestamp from deal image filename (e.g., 1234567890_image.jpg)
    if (url.contains('deal_images/')) {
      final match = RegExp(r'(\d+)_').firstMatch(url);
      if (match != null) {
        final timestamp = match.group(1);
        return url.contains('?') ? '$url&t=$timestamp' : '$url?t=$timestamp';
      }
    }
    // Fallback to current time
    final fallback = DateTime.now().millisecondsSinceEpoch.toString();
    return url.contains('?') ? '$url&t=$fallback' : '$url?t=$fallback';
  }

  @override
  void initState() {
    super.initState();
    _selectedCityFilter = widget.cityFilter;
    _loadAvailableDeals();
    _loadAvailableCities();
  }

  Future<void> _loadAvailableCities() async {
    try {
      final cities = await _discountService.getAvailableCities();
      if (mounted) {
        setState(() => _availableCities = cities);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading cities: $e');
      }
    }
  }

  Future<void> _loadAvailableDeals({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      // Get the current user
      final currentUser = SupabaseService.instance.getCurrentUser();
      final userId = currentUser?.id;

      // Fetch deals + completed once-off deals in parallel
      final Set<String> completedOnceOffDealIds = {};
      late final List<Map<String, dynamic>> deals;

      if (!widget.isAdminMode && userId != null) {
        // Member mode: fetch both in parallel
        final results = await Future.wait([
          _discountService.getAllActiveDiscountsWithTrustedPartners(
            forceRefresh: forceRefresh,
          ),
          _discountService.getCompletedDealIdsForMember(userId),
        ]);
        deals = results[0] as List<Map<String, dynamic>>;
        completedOnceOffDealIds.addAll(results[1] as Set<String>);
      } else {
        // Admin mode or no user: just fetch deals
        deals = await _discountService.getAllActiveDiscountsWithTrustedPartners(
          forceRefresh: forceRefresh,
        );
      }

      // Filter deals by schedule - only show available deals
      final availableDeals = deals.where((deal) {
        // Hide completed once-off deals from this member
        final isOnceOff = (deal['is_once_off'] as bool?) ?? false;
        if (isOnceOff && userId != null) {
          if (completedOnceOffDealIds.contains(deal['id'])) {
            if (kDebugMode) {
              print(
                '⏰ Hiding once-off deal "${deal['name']}" - already redeemed',
              );
            }
            return false;
          }
        }

        final scheduleData = deal['schedule_data'] as Map<String, dynamic>?;

        if (scheduleData == null || scheduleData.isEmpty) {
          // No schedule = always available
          return true;
        }

        try {
          final schedule = DealSchedule.fromJson(scheduleData);
          final isAvailable = schedule.isAvailableNow();

          if (kDebugMode && !isAvailable) {
            print(
              '⏰ Hiding scheduled deal "${deal['name']}" - not available now',
            );
          }

          return isAvailable;
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Error parsing schedule for "${deal['name']}": $e');
          }
          // If schedule parsing fails, show the deal
          return true;
        }
      }).toList();

      if (kDebugMode) {
        print(
          '✅ Browse Deals: Filtered to ${availableDeals.length} available deals (from ${deals.length} total)',
        );
      }

      // Group deals by partner
      final dealsByPartner = <String, List<Map<String, dynamic>>>{};
      for (final deal in availableDeals) {
        final trustedPartner =
            deal['trusted_partners'] as Map<String, dynamic>?;
        final businessName =
            trustedPartner?['business_name'] ?? 'Unknown Partner';

        if (!dealsByPartner.containsKey(businessName)) {
          dealsByPartner[businessName] = [];
        }
        dealsByPartner[businessName]!.add(deal);
      }

      // Sort partners alphabetically
      final sortedPartners =
          Map<String, List<Map<String, dynamic>>>.fromEntries(
            dealsByPartner.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)),
          );

      // Extract deal categories and types
      final dealTypes = <String>{};

      for (final deal in availableDeals) {
        // BUSINESS CATEGORY: Extract from trusted_partners data (stored for completeness)
        final trustedPartner =
            deal['trusted_partners'] as Map<String, dynamic>?;
        final businessCategory =
            trustedPartner?['category']?.toString() ??
            deal['business_category']?.toString();

        if (businessCategory != null && businessCategory.isNotEmpty) {
          deal['business_category'] = businessCategory;
        }

        // DEAL CATEGORY: Extract from deal_category field (for Deals mode filter)
        final dealCategory = deal['deal_category']?.toString();
        if (dealCategory != null && dealCategory.isNotEmpty) {
          deal['deal_category_filter'] = dealCategory;
        } else {
          deal['deal_category_filter'] = 'Other';
        }

        // Extract deal type
        final isBillDiscount = (deal['is_bill_discount'] as bool?) ?? false;
        final isWeightBased = (deal['is_weight_based'] as bool?) ?? false;
        final isOnceOff = (deal['is_once_off'] as bool?) ?? false;
        final rawDealType = deal['deal_type']?.toString();

        // Map raw deal type to display label
        String dealTypeLabel;
        String dealTypeKey;
        if (rawDealType == Discount.websiteRedirectType) {
          dealTypeKey = Discount.websiteRedirectType;
          dealTypeLabel = 'Website Deal';
        } else if (rawDealType == Discount.bookingRedirectType) {
          dealTypeKey = Discount.bookingRedirectType;
          dealTypeLabel = 'Booking Deal';
        } else if (RestaurantDealType.isRestaurantKey(rawDealType)) {
          dealTypeKey = rawDealType!;
          dealTypeLabel = 'Restaurant Deal';
        } else if (rawDealType == 'buy_get') {
          dealTypeKey = 'buy_get';
          dealTypeLabel = 'Buy/Get';
        } else if (rawDealType == 'percent_item') {
          dealTypeKey = 'percent_item';
          dealTypeLabel = '% Off Item';
        } else if (rawDealType == 'free_delivery') {
          dealTypeKey = 'free_delivery';
          dealTypeLabel = 'Free Delivery';
        } else if (isBillDiscount) {
          dealTypeKey = 'bill_discount';
          dealTypeLabel = 'Bill Discount';
        } else if (isOnceOff) {
          dealTypeKey = 'once_off';
          dealTypeLabel = 'Once-Off Deal';
        } else if (isWeightBased) {
          dealTypeKey = 'weight';
          dealTypeLabel = 'Weight-Based';
        } else {
          dealTypeKey = 'standard';
          dealTypeLabel = 'Standard Deal';
        }

        dealTypes.add(dealTypeLabel);
        deal['deal_type'] = dealTypeKey; // keep raw type for downstream logic
        deal['deal_type_label'] = dealTypeLabel;

        if (kDebugMode) {
          print(
            '🏷️ Deal: ${deal['name']}, Deal Category: $dealCategory, Type: $dealTypeLabel',
          );
        }
      }

      if (kDebugMode) {
        print('📋 Total deal types found: ${dealTypes.length}');
        print('📋 Deal types: $dealTypes');
      }

      setState(() {
        _dealsByPartner = sortedPartners;
        _filteredDealsByPartner = sortedPartners;
        _allDeals = availableDeals;
        _availableDealTypes = dealTypes.toList()..sort();
        _isLoading = false;
      });

      // Apply filters after loading
      _applyFilters();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load available deals: $e'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  void _requestDealAuthorization(Map<String, dynamic> deal) {
    if (widget.isAdminMode) {
      _editDealAsAdmin(deal);
      return;
    }
    if (_isWebsiteRedirect(deal)) {
      _openWebsiteRedirect(deal);
      return;
    }
    if (_isBookingRedirect(deal)) {
      _openBookingRedirect(deal);
      return;
    }
    if (_isRestaurantDeal(deal)) {
      final discount = Discount.fromJson(deal);
      if (discount.restaurantConfig == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please update the app to use this deal.'),
          ),
        );
        return;
      }
      final partner = deal['trusted_partners'] as Map<String, dynamic>?;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RestaurantDealRequestPage(
            discount: discount,
            partnerName: partner?['business_name'] as String?,
          ),
        ),
      );
      return;
    }
    final dealId = deal['id'] as String;
    final isWeightBased = (deal['is_weight_based'] as bool?) ?? false;
    final quantity = _quantities[dealId] ?? (isWeightBased ? 100 : 1);

    // Pass quantity along with deal data
    final dealWithQuantity = {...deal, 'quantity': quantity};

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            DealAuthorizationRequestPage(deal: dealWithQuantity),
      ),
    );
  }

  final Logger _adminLogger = Logger();

  bool _isWebsiteRedirect(Map<String, dynamic> deal) =>
      deal['deal_type'] == Discount.websiteRedirectType;

  bool _isBookingRedirect(Map<String, dynamic> deal) =>
      deal['deal_type'] == Discount.bookingRedirectType;

  bool _isRestaurantDeal(Map<String, dynamic> deal) =>
      RestaurantDealType.isRestaurantKey(deal['deal_type']?.toString());

  Future<void> _openWebsiteRedirect(Map<String, dynamic> deal) {
    final partner = deal['trusted_partners'] as Map<String, dynamic>?;
    return openWebsiteRedirectDeal(
      context,
      dealId: deal['id'] as String,
      trustedPartnerId: deal['trusted_partner_id'] as String?,
      partnerName: (partner?['business_name'] as String?) ?? 'Trusted Partner',
      websiteUrl: partner?['website_url'] as String?,
      logoUrl: partner?['logo_url'] as String?,
    );
  }

  Future<void> _openBookingRedirect(Map<String, dynamic> deal) {
    final partner = deal['trusted_partners'] as Map<String, dynamic>?;
    final customData = deal['custom_data'] as Map<String, dynamic>?;
    return openBookingRedirectDeal(
      context,
      dealId: deal['id'] as String,
      trustedPartnerId: deal['trusted_partner_id'] as String?,
      partnerName: (partner?['business_name'] as String?) ?? 'Trusted Partner',
      bookingUrl: customData?['booking_url'] as String?,
      logoUrl: partner?['logo_url'] as String?,
    );
  }

  Widget _buildVisitWebsiteBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kBrandBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kBrandBlue.withOpacity(0.35)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.language, size: 14, color: _kBrandBlue),
          SizedBox(width: 4),
          Text(
            'Visit Website',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _kBrandBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookNowBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kBrandBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kBrandBlue.withOpacity(0.35)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sports_tennis, size: 14, color: _kBrandBlue),
          SizedBox(width: 4),
          Text(
            'Book Now',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _kBrandBlue,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editDealAsAdmin(Map<String, dynamic> deal) async {
    if (_isRestaurantDeal(deal)) {
      final discount = Discount.fromJson(deal);
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) => RestaurantDealDialog(
          trustedPartnerId: discount.trustedPartnerId,
          existing: discount,
        ),
      );
      if (saved == true && mounted) {
        await _loadAvailableDeals(forceRefresh: true);
      }
      return;
    }
    if (_isWebsiteRedirect(deal)) {
      final discount = Discount.fromJson(deal);
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) => WebsiteRedirectDealDialog(
          trustedPartnerId: discount.trustedPartnerId,
          existing: discount,
        ),
      );
      if (saved == true && mounted) {
        await _loadAvailableDeals(forceRefresh: true);
      }
      return;
    }
    if (_isBookingRedirect(deal)) {
      final discount = Discount.fromJson(deal);
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) => BookingRedirectDealDialog(
          trustedPartnerId: discount.trustedPartnerId,
          existing: discount,
        ),
      );
      if (saved == true && mounted) {
        await _loadAvailableDeals(forceRefresh: true);
      }
      return;
    }
    try {
      final discount = Discount.fromJson(deal);
      final trustedPartnerId =
          deal['trusted_partner_id'] as String? ?? discount.trustedPartnerId;

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => EditDiscountDialog(
          discount: discount,
          trustedPartnerId: trustedPartnerId,
        ),
      );

      if (result != null && mounted) {
        try {
          await DiscountService().updateDiscount(
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
            isOnceOff: result['isOnceOff'],
            updateImageUrl: true,
          );
          DiscountService.invalidateActiveDealsCache();
          await _loadAvailableDeals();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Deal updated successfully'),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 40, left: 16, right: 16),
            ),
          );
        } catch (e) {
          _adminLogger.e('Failed to update deal: $e');
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
    } catch (e) {
      _adminLogger.e('Failed to open edit dialog: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not edit deal: $e'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
        ),
      );
    }
  }

  void _filterDeals(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
    _applyFilters();
  }

  void _applyFilters() {
    setState(() {
      if (_showTrustedPartners) {
        // Trusted Partners mode - filter by business category and city
        _filteredDealsByPartner = {};

        _dealsByPartner.forEach((partnerName, deals) {
          // City filter: check if ANY deal from this partner matches the city
          if (_selectedCityFilter != null) {
            final hasMatchingCity = deals.any((deal) {
              final dealCity = (deal['city'] as String?)?.trim();
              final bizCity = (deal['business_city'] as String?)?.trim();
              return dealCity == _selectedCityFilter ||
                  bizCity == _selectedCityFilter;
            });
            if (!hasMatchingCity) return; // skip entire partner
          }

          // Apply search filter
          final partnerMatches =
              _searchQuery.isEmpty ||
              partnerName.toLowerCase().contains(_searchQuery);

          final matchingDeals = deals.where((deal) {
            // City filter per deal
            if (_selectedCityFilter != null) {
              final dealCity = (deal['city'] as String?)?.trim();
              final bizCity = (deal['business_city'] as String?)?.trim();
              if (dealCity != _selectedCityFilter &&
                  bizCity != _selectedCityFilter) {
                return false;
              }
            }

            // Search filter
            bool searchMatch = _searchQuery.isEmpty;
            if (!searchMatch) {
              final dealName = (deal['name'] ?? '').toString().toLowerCase();
              final dealDescription = (deal['description'] ?? '')
                  .toString()
                  .toLowerCase();

              searchMatch =
                  dealName.contains(_searchQuery) ||
                  dealDescription.contains(_searchQuery);
            }

            // Deal category filter (Partners mode shares Deals categories)
            bool categoryMatch =
                _selectedPartnerDealCategory == null ||
                (deal['deal_category_filter']?.toString() ==
                    _selectedPartnerDealCategory);

            return searchMatch && categoryMatch;
          }).toList();

          // Include partner if partner name matches OR has matching deals
          if (partnerMatches &&
              (_selectedPartnerDealCategory == null ||
                  matchingDeals.isNotEmpty)) {
            _filteredDealsByPartner[partnerName] =
                _selectedPartnerDealCategory == null ? deals : matchingDeals;
          } else if (matchingDeals.isNotEmpty) {
            _filteredDealsByPartner[partnerName] = matchingDeals;
          }
        });
      }
      // Deals mode filtering is handled in the build method
    });
  }

  List<Map<String, dynamic>> _getFilteredDeals() {
    // For deals view mode - return flat list of deals
    var filteredDeals = _allDeals.where((deal) {
      // City filter
      if (_selectedCityFilter != null) {
        final dealCity = (deal['city'] as String?)?.trim();
        final bizCity = (deal['business_city'] as String?)?.trim();
        if (dealCity != _selectedCityFilter && bizCity != _selectedCityFilter) {
          return false;
        }
      }

      // Search filter
      bool searchMatch = _searchQuery.isEmpty;
      if (!searchMatch) {
        final dealName = (deal['name'] ?? '').toString().toLowerCase();
        final dealDescription = (deal['description'] ?? '')
            .toString()
            .toLowerCase();
        final trustedPartner =
            deal['trusted_partners'] as Map<String, dynamic>?;
        final partnerName = (trustedPartner?['business_name'] ?? '')
            .toString()
            .toLowerCase();

        searchMatch =
            dealName.contains(_searchQuery) ||
            dealDescription.contains(_searchQuery) ||
            partnerName.contains(_searchQuery);
      }

      // Category filter - use deal_category for Deals mode
      bool categoryMatch =
          _selectedDealCategory == null ||
          (deal['deal_category']?.toString() == _selectedDealCategory);

      // Deal type filter
      final dynamic dealTypeLabel =
          deal['deal_type_label'] ?? deal['deal_type'];
      bool dealTypeMatch =
          _selectedDealType == null ||
          (dealTypeLabel?.toString() == _selectedDealType);

      return searchMatch && categoryMatch && dealTypeMatch;
    }).toList();

    // Sort alphabetically by deal name
    filteredDeals.sort((a, b) {
      final aName = (a['name'] ?? '').toString();
      final bName = (b['name'] ?? '').toString();
      return aName.compareTo(bName);
    });

    return filteredDeals;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: Text(
          widget.isAdminMode ? 'Browse Deals (Admin)' : 'Browse Deals',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadAvailableDeals(forceRefresh: true),
            tooltip: 'Refresh deals',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search section
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: _filterDeals,
              decoration: InputDecoration(
                hintText: 'Search by partner name or deal category...',
                prefixIcon: const Icon(Icons.search, color: _kBrandBlue),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _filterDeals('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kBrandBlue),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kBrandBlue, width: 2),
                ),
                filled: true,
                fillColor: _kBrandBlue.withOpacity(0.08),
              ),
            ),
          ),

          // City/Area Filter
          if (_availableCities.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedCityFilter != null
                        ? _kAccentGreen
                        : _kBrandBlue.withOpacity(0.25),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedCityFilter,
                    hint: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'All Regions',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                    icon: _selectedCityFilter != null
                        ? GestureDetector(
                            onTap: () {
                              setState(() => _selectedCityFilter = null);
                              _applyFilters();
                            },
                            child: const Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.grey,
                            ),
                          )
                        : Icon(
                            Icons.arrow_drop_down,
                            color: _kBrandBlue.withOpacity(0.7),
                          ),
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Row(
                          children: [
                            Icon(Icons.public, size: 16, color: Colors.grey),
                            SizedBox(width: 6),
                            Text('All Regions', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      ..._availableCities.map((city) {
                        return DropdownMenuItem<String>(
                          value: city,
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_city,
                                size: 16,
                                color: _kBrandGreen,
                              ),
                              SizedBox(width: 6),
                              Text(city, style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedCityFilter = value);
                      _applyFilters();
                    },
                  ),
                ),
              ),
            ),

          if (_availableCities.isNotEmpty) const SizedBox(height: 8),

          // Toggle and Category Filter Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Toggle: Trusted Partners / Deals
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kBrandBlue.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _showTrustedPartners = true;
                                // Reset Deals mode filters when switching to Partners
                                _selectedDealCategory = null;
                                _selectedDealType = null;
                              });
                              _applyFilters();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _showTrustedPartners
                                    ? _kBrandBlue
                                    : Colors.transparent,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(11),
                                  bottomLeft: Radius.circular(11),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.business,
                                    size: 16,
                                    color: _showTrustedPartners
                                        ? Colors.white
                                        : _kBrandBlue,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Partners',
                                    style: TextStyle(
                                      color: _showTrustedPartners
                                          ? Colors.white
                                          : _kBrandBlue,
                                      fontWeight: _showTrustedPartners
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _showTrustedPartners = false;
                                // Reset Partners mode filters when switching to Deals
                                _selectedPartnerDealCategory = null;
                              });
                              _applyFilters();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !_showTrustedPartners
                                    ? _kBrandBlue
                                    : Colors.transparent,
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(11),
                                  bottomRight: Radius.circular(11),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.local_offer,
                                    size: 16,
                                    color: !_showTrustedPartners
                                        ? Colors.white
                                        : _kBrandBlue,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Deals',
                                    style: TextStyle(
                                      color: !_showTrustedPartners
                                          ? Colors.white
                                          : _kBrandBlue,
                                      fontWeight: !_showTrustedPartners
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Category Dropdown - Same deal categories for both modes
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kBrandBlue.withOpacity(0.25)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: _showTrustedPartners
                          ? // PARTNERS MODE: Deal Category Dropdown (mirrors Deals categories)
                            DropdownButton<String>(
                              isExpanded: true,
                              value: _selectedPartnerDealCategory,
                              hint: Row(
                                children: [
                                  Icon(
                                    Icons.local_offer,
                                    size: 16,
                                    color: _kBrandBlue.withOpacity(0.7),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'All Deal Categories',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              icon: Icon(
                                Icons.arrow_drop_down,
                                color: _kBrandBlue.withOpacity(0.7),
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text(
                                    'All Deal Categories',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                ..._availableDealCategories.map((category) {
                                  return DropdownMenuItem<String>(
                                    value: category,
                                    child: Text(
                                      category,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (value) {
                                if (kDebugMode) {
                                  print(
                                    '🏷️ Partner Deal Category selected: $value',
                                  );
                                }
                                setState(() {
                                  _selectedPartnerDealCategory = value;
                                });
                                _applyFilters();
                              },
                            )
                          : // DEALS MODE: Deal Category Dropdown
                            DropdownButton<String>(
                              isExpanded: true,
                              value: _selectedDealCategory,
                              hint: Row(
                                children: [
                                  Icon(
                                    Icons.local_offer,
                                    size: 16,
                                    color: _kBrandBlue.withOpacity(0.7),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'All Deal Categories',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              icon: Icon(
                                Icons.arrow_drop_down,
                                color: _kBrandBlue.withOpacity(0.7),
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text(
                                    'All Deal Categories',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                ..._availableDealCategories.map((category) {
                                  return DropdownMenuItem<String>(
                                    value: category,
                                    child: Text(
                                      category,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (value) {
                                if (kDebugMode) {
                                  print('🏷️ Deal Category selected: $value');
                                }
                                setState(() {
                                  _selectedDealCategory = value;
                                });
                                _applyFilters();
                              },
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Deal Type Dropdown (only visible in Deals mode)
          if (!_showTrustedPartners)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBrandBlue.withOpacity(0.25)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedDealType,
                    hint: Row(
                      children: [
                        Icon(
                          Icons.label,
                          size: 16,
                          color: _kBrandBlue.withOpacity(0.7),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'All Deal Types',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: _kBrandBlue.withOpacity(0.7),
                    ),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text(
                          'All Deal Types',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      ..._availableDealTypes.map((dealType) {
                        return DropdownMenuItem<String>(
                          value: dealType,
                          child: Text(
                            dealType,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      if (kDebugMode) {
                        print('🏷️ Deal type selected: $value');
                      }
                      setState(() {
                        _selectedDealType = value;
                      });
                      _applyFilters();
                    },
                  ),
                ),
              ),
            ),

          // Header section
          Container(
            padding: const EdgeInsets.all(16),
            color: _kBrandBlue.withOpacity(0.08),
            child: Row(
              children: [
                Icon(
                  _showTrustedPartners ? Icons.business : Icons.local_offer,
                  size: 32,
                  color: _kBrandBlue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _showTrustedPartners
                            ? 'Trusted Partners'
                            : 'Available Deals',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _kBrandBlue,
                        ),
                      ),
                      Text(
                        _showTrustedPartners
                            ? 'Browse partners and their exclusive deals'
                            : 'All deals sorted alphabetically',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      if (_searchQuery.isNotEmpty ||
                          _selectedPartnerDealCategory != null ||
                          _selectedDealType != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              if (_searchQuery.isNotEmpty)
                                Text(
                                  'Search: "$_searchQuery"',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _kBrandBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (_showTrustedPartners &&
                                  _selectedPartnerDealCategory != null)
                                Text(
                                  'Category: $_selectedPartnerDealCategory',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _kBrandBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (!_showTrustedPartners &&
                                  _selectedDealCategory != null)
                                Text(
                                  'Category: $_selectedDealCategory',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _kBrandBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (_selectedDealType != null)
                                Text(
                                  'Type: $_selectedDealType',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _kBrandBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _showTrustedPartners
                ? (_filteredDealsByPartner.isEmpty
                      ? _buildEmptyState()
                      : _buildPartnersList())
                : (_getFilteredDeals().isEmpty
                      ? _buildEmptyState()
                      : _buildDealsList()),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _showTrustedPartners
                ? Icons.business_outlined
                : Icons.local_offer_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            _showTrustedPartners ? 'No partners found' : 'No deals available',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty ||
                    _selectedPartnerDealCategory != null ||
                    _selectedDealCategory != null
                ? 'Try adjusting your filters'
                : 'Check back later for new deals from trusted partners',
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadAvailableDeals,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildDealsList() {
    final filteredDeals = _getFilteredDeals();

    return RefreshIndicator(
      onRefresh: _loadAvailableDeals,
      child: ListView.builder(
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 100,
        ),
        itemCount: filteredDeals.length,
        itemBuilder: (context, index) {
          final deal = filteredDeals[index];
          return _buildDealCardWithPartner(deal);
        },
      ),
    );
  }

  Widget _buildDealCardWithPartner(Map<String, dynamic> deal) {
    final trustedPartner = deal['trusted_partners'] as Map<String, dynamic>?;
    final partnerName = trustedPartner?['business_name'] ?? 'Unknown Partner';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _requestDealAuthorization(deal),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Partner name badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _kBrandBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _kBrandBlue.withOpacity(0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.business, size: 12, color: _kBrandBlue),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        partnerName,
                        style: TextStyle(
                          fontSize: 11,
                          color: _kBrandBlue,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Deal card content (reuse existing deal card UI)
              _buildDealCardContent(deal),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDealCardContent(Map<String, dynamic> deal) {
    final dealName = deal['name'] ?? 'Unnamed Deal';
    final dealDescription = deal['description'] ?? '';
    final discount = deal['discount'] ?? 0.0;
    final isBillDiscount = (deal['is_bill_discount'] as bool?) ?? false;
    final isPercentItem = (deal['is_percent_item'] as bool?) ?? false;
    final isWeightBased = (deal['is_weight_based'] as bool?) ?? false;
    final itemPrice = (deal['item_price'] as num?)?.toDouble() ?? 0.0;
    final fixedAmount = (deal['fixed_amount'] as num?)?.toDouble() ?? 0.0;
    final percentage = (deal['percentage'] as num?)?.toDouble() ?? 0.0;
    final imageUrl = deal['image_url'] as String?;
    final itemName = deal['item_name'] ?? '';
    final isActive = (deal['is_active'] as bool?) ?? true;
    final isWebsiteRedirect = _isWebsiteRedirect(deal);
    final isBookingRedirect = _isBookingRedirect(deal);

    // Calculate deal price and savings
    double dealPrice;
    double savings;
    if (fixedAmount > 0) {
      dealPrice = itemPrice - fixedAmount;
      savings = fixedAmount;
    } else if (percentage > 0) {
      dealPrice = itemPrice * (1 - percentage / 100);
      savings = itemPrice - dealPrice;
    } else {
      dealPrice = itemPrice;
      savings = 0.0;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Deal Image
        if (imageUrl != null && imageUrl.isNotEmpty)
          _buildCompactDealImageThumbnail(
            imageUrl: imageUrl,
            dealName: dealName,
            dealId: deal['id'] as String,
            isBillDiscount: isBillDiscount,
          )
        else
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _kBrandBlue.withOpacity(0.7),
                  _kBrandGreen.withOpacity(0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isBillDiscount ? Icons.receipt_long : Icons.local_offer,
              size: 32,
              color: Colors.white70,
            ),
          ),
        const SizedBox(width: 12),
        // Deal Information
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Deal Name
              Text(
                dealName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),

              // Description
              Text(
                dealDescription,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Deal Details - Compact
              if (isWebsiteRedirect)
                _buildVisitWebsiteBadge()
              else if (isBookingRedirect)
                _buildBookNowBadge()
              else if (_isRestaurantDeal(deal))
                RestaurantDealBadge(
                  dealType: deal['deal_type']?.toString(),
                  customData: deal['custom_data'] as Map<String, dynamic>?,
                  scheduleData: deal['schedule_data'] as Map<String, dynamic>?,
                )
              else if (isBillDiscount)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _kAccentGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kAccentGreen),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.discount, size: 14, color: _kBrandGreen),
                      const SizedBox(width: 4),
                      Text(
                        discount > 0
                            ? '${discount.toStringAsFixed(0)}% off bill'
                            : 'R${fixedAmount.toStringAsFixed(2)} off bill',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _kBrandGreen,
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
                    if (itemName.isNotEmpty)
                      Text(
                        itemName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _kBrandBlue,
                        ),
                      ),
                    if (isPercentItem) ...[
                      Text(
                        'Member enters price',
                        style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _kAccentGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${discount.toStringAsFixed(0)}% OFF',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _kAccentGreen,
                          ),
                        ),
                      ),
                    ] else ...[
                      Text(
                        isWeightBased
                            ? 'R${itemPrice.toStringAsFixed(2)}/kg'
                            : 'R${itemPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 11,
                          decoration: TextDecoration.lineThrough,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        isWeightBased
                            ? 'R${dealPrice.toStringAsFixed(2)}/kg'
                            : 'R${dealPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _kAccentGreen,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _kAccentGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isWeightBased
                              ? 'Save R${savings.toStringAsFixed(2)}/kg'
                              : 'Save R${savings.toStringAsFixed(2)}',
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

              // Status Badge & Request Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? _kAccentGreen.withOpacity(0.2)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isActive ? Icons.check_circle : Icons.cancel,
                          size: 12,
                          color: isActive ? _kBrandGreen : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isActive
                                ? _kBrandGreen
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isActive || widget.isAdminMode)
                    ElevatedButton.icon(
                      onPressed: () => _requestDealAuthorization(deal),
                      icon: Icon(
                        widget.isAdminMode
                            ? Icons.edit
                            : isWebsiteRedirect || isBookingRedirect
                            ? Icons.open_in_new
                            : Icons.shopping_cart,
                        size: 14,
                      ),
                      label: Text(
                        widget.isAdminMode
                            ? 'Edit'
                            : isWebsiteRedirect
                            ? 'Visit'
                            : isBookingRedirect
                            ? 'Book'
                            : 'Request',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.isAdminMode
                            ? _kBrandGreen
                            : _kBrandGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
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
    );
  }

  Widget _buildPartnersList() {
    return RefreshIndicator(
      onRefresh: _loadAvailableDeals,
      child: ListView.builder(
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 100,
        ),
        itemCount: _filteredDealsByPartner.length,
        itemBuilder: (context, index) {
          final partnerName = _filteredDealsByPartner.keys.elementAt(index);
          final deals = _filteredDealsByPartner[partnerName]!;
          final isExpanded = _expandedPartners[partnerName] ?? false;

          return _buildPartnerCard(partnerName, deals, isExpanded);
        },
      ),
    );
  }

  Widget _buildPartnerCard(
    String partnerName,
    List<Map<String, dynamic>> deals,
    bool isExpanded,
  ) {
    // Helper to add cache-buster from filename timestamp
    String displayUrl(String url) {
      final match = RegExp(r'logo_(\d+)\.').firstMatch(url);
      final token =
          match?.group(1) ?? DateTime.now().millisecondsSinceEpoch.toString();
      return url.contains('?') ? '$url&t=$token' : '$url?t=$token';
    }

    // Get logo URL and social media from the first deal's trusted_partners data
    String? logoUrl;
    String? facebookHandle;
    String? instagramHandle;
    String? websiteUrl;
    String? businessEmail;

    if (deals.isNotEmpty) {
      final trustedPartners =
          deals.first['trusted_partners'] as Map<String, dynamic>?;
      logoUrl = trustedPartners?['logo_url'] as String?;
      facebookHandle = trustedPartners?['facebook_handle'] as String?;
      instagramHandle = trustedPartners?['instagram_handle'] as String?;
      websiteUrl = trustedPartners?['website_url'] as String?;
      businessEmail = trustedPartners?['business_email'] as String?;

      // Debug: Log what we're getting
      if (kDebugMode) {
        print('🖼️ Partner: $partnerName');
        print('🖼️ Logo URL: $logoUrl');
        print('🖼️ Trusted Partners data: $trustedPartners');
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Partner header - clickable to expand/collapse
          InkWell(
            onTap: () {
              setState(() {
                // Close all other partners first
                _expandedPartners.updateAll((key, value) => false);
                // Then toggle the clicked partner
                _expandedPartners[partnerName] = !isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Business Logo or Icon
                  if (logoUrl != null && logoUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        displayUrl(logoUrl),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _kBrandBlue.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.business,
                              color: _kBrandBlue,
                              size: 28,
                            ),
                          );
                        },
                      ),
                    )
                  else
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _kBrandBlue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.business,
                        color: _kBrandBlue,
                        size: 28,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          partnerName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _kBrandBlue,
                          ),
                        ),
                        Text(
                          '${deals.length} deal${deals.length == 1 ? '' : 's'} available',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        // Social media icons
                        if (_hasSocialMedia(
                          facebookHandle,
                          instagramHandle,
                          websiteUrl,
                          businessEmail,
                        ))
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                if (facebookHandle != null &&
                                    facebookHandle.isNotEmpty)
                                  InkWell(
                                    onTap: () => _launchUrl(
                                      _formatFacebookUrl(facebookHandle!),
                                    ),
                                    child: const Icon(
                                      Icons.facebook,
                                      color: Color(0xFF1877F2),
                                      size: 20,
                                    ),
                                  ),
                                if (facebookHandle != null &&
                                    facebookHandle.isNotEmpty)
                                  const SizedBox(width: 12),
                                if (instagramHandle != null &&
                                    instagramHandle.isNotEmpty)
                                  InkWell(
                                    onTap: () => _launchUrl(
                                      _formatInstagramUrl(instagramHandle!),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Color(0xFFE4405F),
                                      size: 20,
                                    ),
                                  ),
                                if (instagramHandle != null &&
                                    instagramHandle.isNotEmpty)
                                  const SizedBox(width: 12),
                                if (websiteUrl != null && websiteUrl.isNotEmpty)
                                  InkWell(
                                    onTap: () => _launchUrl(websiteUrl!),
                                    child: const Icon(
                                      Icons.language,
                                      color: Color(0xFF4CAF50),
                                      size: 20,
                                    ),
                                  ),
                                if (websiteUrl != null && websiteUrl.isNotEmpty)
                                  const SizedBox(width: 12),
                                if (businessEmail != null &&
                                    businessEmail.isNotEmpty)
                                  InkWell(
                                    onTap: () =>
                                        _launchUrl('mailto:$businessEmail'),
                                    child: const Icon(
                                      Icons.email,
                                      color: Color(0xFFFF9800),
                                      size: 20,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),

          // Expanded deals list
          if (isExpanded) ...[
            const Divider(height: 1),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: deals.length,
              itemBuilder: (context, index) {
                final deal = deals[index];
                return _buildDealCard(deal);
              },
            ),
          ],
        ],
      ),
    );
  }

  void _showBillDiscountDialog(Map<String, dynamic> deal) {
    final discount = Discount.fromJson(deal);
    final trustedPartner = deal['trusted_partners'] as Map<String, dynamic>?;

    showDialog(
      context: context,
      builder: (context) => BillDiscountDialog(
        discount: discount,
        trustedPartnerName:
            trustedPartner?['business_name'] ?? 'Unknown Partner',
        deal: deal,
      ),
    );
  }

  void _showFullSizeImage(String imageUrl, String dealName, String dealId) {
    if (!widget.isAdminMode) {
      unawaited(AdminEngagementService().recordDealOpen(dealId));
    }
    final displayUrl = _displayDealImageUrl(imageUrl);

    showDialog(
      context: context,
      builder: (context) => DealImagePreview(
        imageUrl: displayUrl,
        dealName: dealName,
      ),
    );
  }

  Widget _buildDealImageThumbnail({
    required String imageUrl,
    required String dealName,
    required Discount discount,
  }) {
    return GestureDetector(
      onTap: () => _showFullSizeImage(imageUrl, dealName, discount.id),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          _displayDealImageUrl(imageUrl),
          width: 120,
          height: 120,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _kBrandBlue.withOpacity(0.5),
                    _kBrandGreen.withOpacity(0.5),
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
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: 120,
              height: 120,
              color: Colors.grey.shade200,
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBillDiscountImageThumbnail({
    required String imageUrl,
    required String dealName,
    required String dealId,
  }) {
    return GestureDetector(
      onTap: () => _showFullSizeImage(imageUrl, dealName, dealId),
      child: Container(
        width: 60,
        height: 60,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.network(
            _displayDealImageUrl(imageUrl),
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                color: Colors.grey.shade100,
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey.shade200,
                child: const Icon(
                  Icons.broken_image,
                  size: 24,
                  color: Colors.grey,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCompactDealImageThumbnail({
    required String imageUrl,
    required String dealName,
    required String dealId,
    required bool isBillDiscount,
  }) {
    return GestureDetector(
      onTap: () => _showFullSizeImage(imageUrl, dealName, dealId),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          _displayDealImageUrl(imageUrl),
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: 80,
              height: 80,
              color: Colors.grey.shade200,
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _kBrandBlue.withOpacity(0.5),
                    _kBrandGreen.withOpacity(0.5),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isBillDiscount ? Icons.receipt_long : Icons.local_offer,
                size: 32,
                color: Colors.white70,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDealCard(Map<String, dynamic> deal) {
    final discount = Discount.fromJson(deal);
    final isWeightBased = discount.isWeightBased;
    final isBillDiscount = discount.isBillDiscount;

    if (kDebugMode && discount.isBuyGet) {
      print('🔍 BuyGet Deal Debug:');
      print('  customData: ${discount.customData}');
      print('  buy_item_price: ${discount.customData?['buy_item_price']}');
      print('  free_item_value: ${discount.customData?['free_item_value']}');
      print('  buy_item_name: ${discount.customData?['buy_item_name']}');
      print('  free_item_name: ${discount.customData?['free_item_name']}');
      print('  itemPrice: ${discount.itemPrice}');
      print('  dealPrice: ${discount.dealPrice}');
      print('  savings: ${discount.savings}');
    }

    // For bill discount, return a clickable container
    if (isBillDiscount) {
      final imageUrl = deal['image_url'] as String?;
      return InkWell(
        onTap: () => _showBillDiscountDialog(deal),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300, width: 1),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Image thumbnail if available
                  if (imageUrl != null) ...[
                    _buildBillDiscountImageThumbnail(
                      imageUrl: imageUrl,
                      dealName: discount.name,
                      dealId: discount.id,
                    ),
                  ] else ...[
                    const Icon(
                      Icons.receipt_long,
                      color: Colors.orange,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          discount.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_offer,
                      color: Colors.orange,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        discount.billDiscountData?['isPercentage'] == true
                            ? '${discount.percentage.toStringAsFixed(0)}% off bill'
                            : 'R${discount.fixedAmount?.toStringAsFixed(2)} off bill',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.orange,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // For weight-based deals, quantity represents grams; for others, item count
    // Once-off deals are always quantity 1

    if (isWeightBased) {
      // Formula: (R/kg × total grams) / 1000
      // totalPrice = (discount.dealPrice * quantity) / 1000;
      // totalSavings = (discount.savings * quantity) / 1000;
    } else {
      // Regular multiplication
      // totalPrice = discount.dealPrice * quantity;
      // totalSavings = discount.savings * quantity;
    }

    final imageUrl = deal['image_url'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _requestDealAuthorization(deal),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Deal Image - Left Side (Full Height)
              if (hasImage)
                _buildDealImageThumbnail(
                  imageUrl: imageUrl,
                  dealName: discount.name,
                  discount: discount,
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
                        _kBrandBlue.withOpacity(0.7),
                        _kBrandGreen.withOpacity(0.7),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Deal Name
                    Text(
                      discount.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Description
                    Text(
                      discount.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // Deal Details - Compact
                    if (discount.isWebsiteRedirect)
                      _buildVisitWebsiteBadge()
                    else if (discount.isBookingRedirect)
                      _buildBookNowBadge()
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
                          color: _kAccentGreen.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _kAccentGreen),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.discount, size: 14, color: _kBrandGreen),
                            const SizedBox(width: 4),
                            Text(
                              discount.percentage > 0
                                  ? '${discount.percentage.toStringAsFixed(0)}% off bill'
                                  : 'R${discount.fixedAmount?.toStringAsFixed(2)} off bill',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _kBrandGreen,
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
                          Text(
                            discount.itemName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _kBrandBlue,
                            ),
                          ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _kAccentGreen.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
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
                          ] else ...[
                            Text(
                              discount.isWeightBased
                                  ? 'R${discount.itemPrice.toStringAsFixed(2)}/kg'
                                  : 'R${discount.itemPrice.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 11,
                                decoration: TextDecoration.lineThrough,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _kAccentGreen.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: discount.isActive
                                ? _kAccentGreen.withOpacity(0.2)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
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
                                    ? _kBrandGreen
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                discount.isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: discount.isActive
                                      ? _kBrandGreen
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (discount.isActive || widget.isAdminMode)
                          ElevatedButton.icon(
                            onPressed: () => _requestDealAuthorization(deal),
                            icon: Icon(
                              widget.isAdminMode
                                  ? Icons.edit
                                  : discount.isWebsiteRedirect || discount.isBookingRedirect
                                  ? Icons.open_in_new
                                  : Icons.shopping_cart,
                              size: 14,
                            ),
                            label: Text(
                              widget.isAdminMode
                                  ? 'Edit'
                                  : discount.isWebsiteRedirect
                                  ? 'Visit'
                                  : discount.isBookingRedirect
                                  ? 'Book'
                                  : 'Request',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.isAdminMode
                                  ? _kBrandGreen
                                  : _kBrandGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              textStyle: const TextStyle(fontSize: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
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
    );
  }

  // Helper method to check if any social media is available
  bool _hasSocialMedia(
    String? facebook,
    String? instagram,
    String? website,
    String? email,
  ) {
    return (facebook != null && facebook.isNotEmpty) ||
        (instagram != null && instagram.isNotEmpty) ||
        (website != null && website.isNotEmpty) ||
        (email != null && email.isNotEmpty);
  }

  // Format Facebook URL
  String _formatFacebookUrl(String handle) {
    if (handle.startsWith('http://') || handle.startsWith('https://')) {
      return handle;
    }
    // Remove @ if present
    final cleanHandle = handle.startsWith('@') ? handle.substring(1) : handle;
    return 'https://facebook.com/$cleanHandle';
  }

  // Format Instagram URL
  String _formatInstagramUrl(String handle) {
    if (handle.startsWith('http://') || handle.startsWith('https://')) {
      return handle;
    }
    // Remove @ if present
    final cleanHandle = handle.startsWith('@') ? handle.substring(1) : handle;
    return 'https://instagram.com/$cleanHandle';
  }

  // Launch URL
  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (kDebugMode) {
        print('Could not launch $url');
      }
    }
  }
}

class BillDiscountDialog extends StatefulWidget {
  final Discount discount;
  final String trustedPartnerName;
  final Map<String, dynamic> deal;

  const BillDiscountDialog({
    super.key,
    required this.discount,
    required this.trustedPartnerName,
    required this.deal,
  });

  @override
  State<BillDiscountDialog> createState() => _BillDiscountDialogState();
}

class _BillDiscountDialogState extends State<BillDiscountDialog> {
  // Brand colors (match deal card)
  static const Color _kRequestGreen = Color(0xFF3C8C44);
  static const Color _kAccentGreen = Color(0xFF7FBBA4);
  static const Color _kBrandBlue = Color(0xFF0E5BA0);

  final TextEditingController _billAmountController = TextEditingController();
  final Map<String, int> _exclusionQuantities =
      {}; // Track quantities for exclusions
  bool _addTip = false;
  bool _tipIsPercentage = true;
  final TextEditingController _tipController = TextEditingController();
  String _paymentMethod =
      'in_app'; // Default to in-app payment (consistent with all other deal types)
  bool? _inAppAvailable; // null while checking partner banking

  @override
  void initState() {
    super.initState();
    unawaited(AdminEngagementService().recordDealOpen(widget.discount.id));
    unawaited(_loadInAppAvailability());
  }

  Future<void> _loadInAppAvailability() async {
    final available = await InAppPaymentAvailabilityService()
        .isAvailableForDiscount(widget.discount.id);
    if (!mounted) return;
    setState(() {
      _inAppAvailable = available;
      if (!available && _paymentMethod == 'in_app') {
        _paymentMethod = 'pos';
      }
    });
  }

  Future<void> _switchToPayInStore() async {
    setState(() {
      _inAppAvailable = false;
      _paymentMethod = 'pos';
    });
    await InAppPaymentAvailabilityService().showUnavailableDialog(
      context,
      discountId: widget.discount.id,
      partnerName: widget.trustedPartnerName,
    );
  }

  Future<void> _selectPaymentMethod(String method) async {
    if (method != 'in_app') {
      setState(() => _paymentMethod = method);
      return;
    }
    final available = _inAppAvailable ??
        await InAppPaymentAvailabilityService().isAvailableForDiscount(
          widget.discount.id,
        );
    if (!mounted) return;
    if (available) {
      setState(() {
        _inAppAvailable = true;
        _paymentMethod = 'in_app';
      });
    } else {
      await _switchToPayInStore();
    }
  }

  @override
  void dispose() {
    _billAmountController.dispose();
    _tipController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getFilteredExclusions() {
    final billDiscountData = widget.discount.billDiscountData;
    if (billDiscountData == null) return [];

    final exclusions = billDiscountData['exclusions'] as List<dynamic>? ?? [];
    final now = DateTime.now();
    final currentDayOfWeek = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][now.weekday - 1];

    return exclusions.map((e) => e as Map<String, dynamic>).where((exclusion) {
      final dayOfWeek = exclusion['dayOfWeek'] as String?;
      final allDays = exclusion['allDays'] == true;
      final daysOfWeek = (exclusion['daysOfWeek'] as List<dynamic>? ?? [])
          .map((day) => day.toString())
          .toSet();
      return allDays ||
          daysOfWeek.contains(currentDayOfWeek) ||
          dayOfWeek == currentDayOfWeek;
    }).toList();
  }

  void _incrementExclusionQuantity(String exclusionName) {
    setState(() {
      _exclusionQuantities[exclusionName] =
          (_exclusionQuantities[exclusionName] ?? 0) + 1;
    });
  }

  void _decrementExclusionQuantity(String exclusionName) {
    setState(() {
      final currentQuantity = _exclusionQuantities[exclusionName] ?? 0;
      if (currentQuantity > 0) {
        _exclusionQuantities[exclusionName] = currentQuantity - 1;
      }
    });
  }

  double _calculateTotal() {
    // Get bill amount
    final billAmount = double.tryParse(_billAmountController.text) ?? 0.0;
    if (billAmount <= 0) return 0.0;

    // Calculate total excluded items
    double totalExcluded = 0.0;
    final filteredExclusions = _getFilteredExclusions();
    for (final exclusion in filteredExclusions) {
      final exclusionName = exclusion['name'] as String;
      final quantity = _exclusionQuantities[exclusionName] ?? 0;
      final amount = (exclusion['amount'] as num).toDouble();
      totalExcluded += quantity * amount;
    }

    // Calculate bill after exclusions (for discount calculation)
    final billAfterExclusions = billAmount - totalExcluded;

    // Apply discount ONLY to the non-excluded amount
    double discountAmount = 0.0;
    final billDiscountData = widget.discount.billDiscountData;
    if (billDiscountData?['isPercentage'] == true) {
      final percentage = widget.discount.percentage;
      discountAmount = billAfterExclusions * (percentage / 100);
    } else {
      discountAmount = widget.discount.fixedAmount ?? 0.0;
    }

    final billAfterDiscount = billAfterExclusions - discountAmount;

    // Add back the excluded items to the final total
    final totalWithExcludedItems = billAfterDiscount + totalExcluded;

    // Apply tip
    if (_addTip) {
      final tipValue = double.tryParse(_tipController.text) ?? 0.0;
      if (_tipIsPercentage) {
        // Tip percentage on the total including excluded items
        return totalWithExcludedItems +
            (totalWithExcludedItems * (tipValue / 100));
      } else {
        // Tip amount added to total
        return totalWithExcludedItems + tipValue;
      }
    }

    return totalWithExcludedItems;
  }

  @override
  Widget build(BuildContext context) {
    final filteredExclusions = _getFilteredExclusions();
    final billAmount = double.tryParse(_billAmountController.text) ?? 0.0;

    // Calculate breakdown
    double totalExcluded = 0.0;
    for (final exclusion in filteredExclusions) {
      final exclusionName = exclusion['name'] as String;
      final quantity = _exclusionQuantities[exclusionName] ?? 0;
      final amount = (exclusion['amount'] as num).toDouble();
      totalExcluded += quantity * amount;
    }

    final billAfterExclusions = billAmount - totalExcluded;

    double discountAmount = 0.0;
    final billDiscountData = widget.discount.billDiscountData;
    if (billDiscountData?['isPercentage'] == true) {
      final percentage = widget.discount.percentage;
      discountAmount = billAfterExclusions * (percentage / 100);
    } else {
      discountAmount = widget.discount.fixedAmount ?? 0.0;
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(
                    Icons.receipt_long,
                    color: Colors.orange,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.trustedPartnerName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _kBrandBlue,
                          ),
                        ),
                        Text(
                          widget.discount.name,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Discount info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_offer,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        billDiscountData?['isPercentage'] == true
                            ? '${widget.discount.percentage.toStringAsFixed(0)}% off your bill'
                            : 'R${widget.discount.fixedAmount?.toStringAsFixed(2)} off your bill',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Bill Amount Field
              const Text(
                'Bill Amount',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _billAmountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Enter your bill amount',
                  prefixText: 'R ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),

              // Payment Method Toggle
              const Text(
                'Payment Method',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment<String>(
                    value: 'pos',
                    label: Text('In-Store Payment'),
                    icon: Icon(Icons.point_of_sale, size: 20),
                  ),
                  ButtonSegment<String>(
                    value: 'in_app',
                    label: Text(
                      'In-App Payment',
                      style: _inAppAvailable == false
                          ? const TextStyle(color: Colors.grey)
                          : null,
                    ),
                    icon: const Icon(Icons.smartphone, size: 20),
                  ),
                ],
                selected: {_paymentMethod},
                onSelectionChanged: (Set<String> newSelection) {
                  _selectPaymentMethod(newSelection.first);
                },
              ),
              if (_inAppAvailable == false) ...[
                const SizedBox(height: 8),
                Text(
                  '${widget.trustedPartnerName} can\'t accept in-app payments yet, so you\'ll pay in store.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
              const SizedBox(height: 20),

              // Excluded Items
              if (filteredExclusions.isNotEmpty) ...[
                const Text(
                  'Excluded Items',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredExclusions.length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, color: Colors.grey.shade300),
                    itemBuilder: (context, index) {
                      final exclusion = filteredExclusions[index];
                      final exclusionName = exclusion['name'] as String;
                      final amount = (exclusion['amount'] as num).toDouble();
                      final quantity = _exclusionQuantities[exclusionName] ?? 0;

                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    exclusionName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'R${amount.toStringAsFixed(2)} each',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    onPressed: () =>
                                        _decrementExclusionQuantity(
                                          exclusionName,
                                        ),
                                    icon: const Icon(Icons.remove, size: 16),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                  ),
                                  Container(
                                    width: 30,
                                    alignment: Alignment.center,
                                    child: Text(
                                      quantity.toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        _incrementExclusionQuantity(
                                          exclusionName,
                                        ),
                                    icon: const Icon(Icons.add, size: 16),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Add Tip Checkbox
              CheckboxListTile(
                value: _addTip,
                onChanged: (value) {
                  setState(() {
                    _addTip = value ?? false;
                  });
                },
                title: const Text(
                  'Add Tip',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),

              // Tip Options
              if (_addTip) ...[
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Percentage'),
                      icon: Icon(Icons.percent, size: 16),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Amount'),
                      icon: Icon(Icons.money, size: 16),
                    ),
                  ],
                  selected: {_tipIsPercentage},
                  onSelectionChanged: (Set<bool> newSelection) {
                    setState(() {
                      _tipIsPercentage = newSelection.first;
                      _tipController.clear();
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tipController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: _tipIsPercentage
                        ? 'Enter tip percentage'
                        : 'Enter tip amount',
                    prefixText: _tipIsPercentage ? '' : 'R ',
                    suffixText: _tipIsPercentage ? '%' : '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),
              ],

              // Breakdown
              if (billAmount > 0) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Breakdown',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildBreakdownRow(
                        'Bill Amount',
                        'R${billAmount.toStringAsFixed(2)}',
                      ),
                      if (totalExcluded > 0)
                        _buildBreakdownRow(
                          'Excluded Items',
                          '-R${totalExcluded.toStringAsFixed(2)}',
                          color: Colors.red,
                        ),
                      if (discountAmount > 0)
                        _buildBreakdownRow(
                          'Discount',
                          '-R${discountAmount.toStringAsFixed(2)}',
                          color: _kAccentGreen,
                        ),
                      if (_addTip && _tipController.text.isNotEmpty) ...[
                        Builder(
                          builder: (context) {
                            final tipValue =
                                double.tryParse(_tipController.text) ?? 0.0;
                            final billAfterDiscount =
                                billAfterExclusions - discountAmount;
                            final tipAmount = _tipIsPercentage
                                ? billAfterDiscount * (tipValue / 100)
                                : tipValue;
                            return _buildBreakdownRow(
                              'Tip',
                              '+R${tipAmount.toStringAsFixed(2)}',
                              color: _kBrandBlue,
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Total Bill
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kBrandBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _kBrandBlue.withOpacity(0.25),
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Bill',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _kBrandBlue,
                      ),
                    ),
                    Text(
                      'R${_calculateTotal().toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _kBrandBlue,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Request Authorization Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: billAmount > 0
                      ? () async {
                          try {
                            final supabaseService = SupabaseService.instance;
                            final currentUser =
                                supabaseService.client.auth.currentUser;

                            if (currentUser == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('User not authenticated'),
                                  behavior: SnackBarBehavior.floating,
                                  margin: EdgeInsets.only(
                                    bottom: 40,
                                    left: 16,
                                    right: 16,
                                  ),
                                ),
                              );
                              return;
                            }

                            // Get business_id from the trusted_partners data
                            final trustedPartner =
                                widget.deal['trusted_partners']
                                    as Map<String, dynamic>?;
                            final businessId =
                                trustedPartner?['business_id'] as String?;

                            if (businessId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Business ID not found'),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                  margin: EdgeInsets.only(
                                    bottom: 40,
                                    left: 16,
                                    right: 16,
                                  ),
                                ),
                              );
                              return;
                            }

                            // Guard: discount must be fully hydrated before
                            // we can create an authorization. Without these
                            // ids the row becomes unreadable on the TP side.
                            final discountId = widget.discount.id;
                            final trustedPartnerUserId =
                                widget.discount.trustedPartnerId;
                            if (discountId.isEmpty ||
                                trustedPartnerUserId.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Deal information is incomplete. Please reopen the deal and try again.',
                                  ),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                  margin: EdgeInsets.only(
                                    bottom: 40,
                                    left: 16,
                                    right: 16,
                                  ),
                                ),
                              );
                              return;
                            }

                            // Calculate the final total and components
                            final totalAmount = _calculateTotal();

                            // Calculate discount amount for tracking
                            final totalExcluded = filteredExclusions
                                .fold<double>(0.0, (sum, exclusion) {
                                  final exclusionName =
                                      exclusion['name'] as String;
                                  final quantity =
                                      _exclusionQuantities[exclusionName] ?? 0;
                                  final amount = (exclusion['amount'] as num)
                                      .toDouble();
                                  return sum + (quantity * amount);
                                });
                            final billAfterExclusions =
                                billAmount - totalExcluded;
                            final billDiscountData =
                                widget.discount.billDiscountData;
                            double discountAmount = 0.0;
                            if (billDiscountData?['isPercentage'] == true) {
                              final percentage = widget.discount.percentage;
                              discountAmount =
                                  billAfterExclusions * (percentage / 100);
                            } else {
                              discountAmount =
                                  widget.discount.fixedAmount ?? 0.0;
                            }

                            // Calculate tip amount
                            double tipAmount = 0.0;
                            if (_addTip) {
                              final tipValue =
                                  double.tryParse(_tipController.text) ?? 0.0;
                              final tipBase =
                                  billAmount - totalExcluded - discountAmount;
                              if (_tipIsPercentage) {
                                tipAmount = tipBase * (tipValue / 100);
                              } else {
                                tipAmount = tipValue;
                              }
                            }

                            // Create the authorization request with detailed bill data
                            await supabaseService.client
                                .from('deal_authorizations')
                                .insert({
                                  'member_id': currentUser.id,
                                  'business_id': businessId,
                                  'trusted_partner_id': trustedPartnerUserId,
                                  'discount_id': discountId,
                                  'status': 'pending',
                                  'amount': totalAmount,
                                  'payment_method': _paymentMethod,
                                  'notes':
                                      'Bill discount request: R${billAmount.toStringAsFixed(2)} bill - ${_paymentMethod == 'pos' ? 'In-Store Payment' : 'In-App Payment'}${_addTip ? ' + Tip: R${tipAmount.toStringAsFixed(2)}' : ''}',
                                  'bill_data': {
                                    'original_bill_amount': billAmount,
                                    'discount_amount': discountAmount,
                                    'excluded_items_total': totalExcluded,
                                    'tip_amount': tipAmount,
                                    'final_amount': totalAmount,
                                  },
                                  'created_at': DateTime.now()
                                      .toIso8601String(),
                                });

                            if (!mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Bill discount authorization request submitted',
                                ),
                                backgroundColor: _kRequestGreen,
                                behavior: SnackBarBehavior.floating,
                                margin: EdgeInsets.only(
                                  bottom: 40,
                                  left: 16,
                                  right: 16,
                                ),
                              ),
                            );
                            Navigator.pop(context);
                            // Note: Savings stats will be refreshed when user returns to the page
                          } catch (e) {
                            if (!mounted) return;

                            if (InAppPaymentAvailabilityService.isUnavailableError(
                              e,
                            )) {
                              await _switchToPayInStore();
                              return;
                            }

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to submit request: $e'),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.only(
                                  bottom: 40,
                                  left: 16,
                                  right: 16,
                                ),
                              ),
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.check_circle),
                  label: const Text(
                    'Request Authorization',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kRequestGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreakdownRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color ?? Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color ?? Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
