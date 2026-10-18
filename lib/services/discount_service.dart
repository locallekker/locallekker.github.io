import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import '../core/constants/deal_categories.dart';
import '../models/discount.dart';
import '../models/deal_authorization.dart';
import '../models/virtual_receipt.dart';
import '../models/notification.dart';
import '../models/member_receipt.dart';
import 'package:flutter/foundation.dart';

/// Visibility + "new deals" state for a category entry banner
/// (Fresh & Local, Local Sips, Local Eats).
class FreshLocalSummary {
  final bool hasPartners;
  final int newDealCount;
  final int partnerCount;
  final int dealCount;

  const FreshLocalSummary({
    this.hasPartners = false,
    this.newDealCount = 0,
    this.partnerCount = 0,
    this.dealCount = 0,
  });
}

class DiscountService {
  static final DiscountService _instance = DiscountService._internal();
  factory DiscountService() => _instance;
  DiscountService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final Logger _logger = Logger();

  Future<List<Discount>> getTrustedPartnerDiscounts(
    String trustedPartnerId,
  ) async {
    try {
      final response = await _supabase
          .from('trusted_partner_discounts')
          .select()
          .eq('trusted_partner_id', trustedPartnerId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      return response.map((json) => Discount.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load discounts: $e');
    }
  }

  /// Get all active deals for a specific city
  /// Returns discounts that are active and associated with the given city
  Future<List<Discount>> getActiveDealsInCity(String city) async {
    try {
      if (city.isEmpty) {
        _logger.w('⚠️ Empty city string provided');
        return [];
      }

      final response = await _supabase
          .from('trusted_partner_discounts')
          .select()
          .eq('city', city)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      _logger.i('🏙️ Found ${response.length} deals in city: $city');
      return response.map((json) => Discount.fromJson(json)).toList();
    } catch (e) {
      _logger.e('Failed to load deals for city $city: $e');
      throw Exception('Failed to load deals: $e');
    }
  }

  /// Get all active deals, filtering by city on the client side
  /// This method fetches all active deals and filters locally
  /// Useful when you want to show a count of ALL deals vs city-specific
  Future<List<Discount>> getAllActiveDeals({String? cityFilter}) async {
    try {
      final response = await _supabase
          .from('trusted_partner_discounts')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false);

      var deals = response.map((json) => Discount.fromJson(json)).toList();

      // Filter by city if provided
      if (cityFilter != null && cityFilter.isNotEmpty) {
        deals = deals.where((deal) {
          // Check if deal has city field and matches
          return deal.customData != null &&
              deal.customData!['city'] == cityFilter;
        }).toList();
        _logger.i(
          '🏙️ Found ${deals.length} deals in city: $cityFilter after filtering',
        );
      } else {
        _logger.i('📊 Found ${deals.length} total active deals');
      }

      return deals;
    } catch (e) {
      _logger.e('Failed to load all deals: $e');
      throw Exception('Failed to load deals: $e');
    }
  }

  /// Get deals near a city (can be extended to support radius-based search)
  /// Currently returns exact city matches, but can be enhanced for nearby areas
  /// Get all distinct cities from businesses and active deals
  /// Returns a sorted list of unique city names for the area filter
  Future<List<String>> getAvailableCities() async {
    try {
      // Fetch cities from businesses and deals in parallel
      final responses = await Future.wait([
        _supabase.from('businesses').select('city'),
        _supabase
            .from('trusted_partner_discounts')
            .select('city')
            .eq('is_active', true),
      ]);

      final businessCities = responses[0] as List;
      final dealCities = responses[1] as List;

      final cities = <String>{};
      for (final row in businessCities) {
        final city = (row['city'] as String?)?.trim();
        if (city != null && city.isNotEmpty) cities.add(city);
      }
      for (final row in dealCities) {
        final city = (row['city'] as String?)?.trim();
        if (city != null && city.isNotEmpty) cities.add(city);
      }

      final sorted = cities.toList()..sort();
      _logger.i('🏙️ Found ${sorted.length} available cities: $sorted');
      return sorted;
    } catch (e) {
      _logger.e('Failed to load available cities: $e');
      return [];
    }
  }

  /// Trusted partners in a curated deal category.
  ///
  /// A partner qualifies by having at least one active deal in [category], or
  /// by matching [businessCategory] or being explicitly flagged ([flagColumn]
  /// on `businesses`) and having any active deal. Each entry carries the
  /// business row plus `deal_count` and `offers_delivery`.
  Future<List<Map<String, dynamic>>> _getCategoryPartners({
    required String category,
    required String logLabel,
    String? flagColumn,
    List<String>? businessCategories,
    String? city,
  }) async {
    final businessCategory =
        (businessCategories == null || businessCategories.isEmpty)
        ? null
        : businessCategories;
    try {
      final results = await Future.wait<dynamic>([
        _supabase
            .from('trusted_partner_discounts')
            .select('trusted_partner_id')
            .eq('is_active', true)
            .eq('deal_category', category),
        if (flagColumn != null)
          _supabase.from('businesses').select('owner_member_id').eq(
            flagColumn,
            true,
          )
        else
          Future.value(<Map<String, dynamic>>[]),
        if (businessCategory != null)
          _supabase
              .from('businesses')
              .select('owner_member_id')
              .inFilter('category', businessCategory)
        else
          Future.value(<Map<String, dynamic>>[]),
      ]);

      final candidateIds = <String>{};
      for (final row in (results[0] as List)) {
        final id = row['trusted_partner_id'] as String?;
        if (id != null) candidateIds.add(id);
      }
      for (final row in (results[1] as List)) {
        final id = row['owner_member_id'] as String?;
        if (id != null) candidateIds.add(id);
      }
      for (final row in (results[2] as List)) {
        final id = row['owner_member_id'] as String?;
        if (id != null) candidateIds.add(id);
      }
      if (candidateIds.isEmpty) {
        _logger.i('🔎 No $logLabel candidates (no category deals, no flags)');
        return [];
      }

      var query = _supabase
          .from('businesses')
          .select(
            'id, owner_member_id, name, category, city, address, logo_url, '
            'produce_description, alcohol_description, liquor_license_verified, '
            'sports_description, '
            'contact_number, contact_email, '
            'facebook_handle, instagram_handle, website_url, business_email',
          )
          .inFilter('owner_member_id', candidateIds.toList());

      if (city != null && city.trim().isNotEmpty) {
        query = query.eq('city', city.trim());
      }
      var businesses = List<Map<String, dynamic>>.from(await query);
      if (businessCategory != null) {
        final categoryDealOwners = {
          for (final row in (results[0] as List))
            if (row['trusted_partner_id'] is String)
              row['trusted_partner_id'] as String,
        };
        // Keep partners in a matching business category, plus any partner
        // who has explicitly created deals in this curated category.
        businesses = businesses
            .where(
              (b) =>
                  businessCategory.contains(b['category']) ||
                  categoryDealOwners.contains(b['owner_member_id']),
            )
            .toList();
      }
      if (businesses.isEmpty) {
        _logger.i('🔎 No $logLabel businesses matched city filter "$city"');
        return [];
      }

      final ownerIds = businesses
          .map((b) => b['owner_member_id'] as String?)
          .whereType<String>()
          .toList();
      if (ownerIds.isEmpty) return [];

      final deals = List<Map<String, dynamic>>.from(
        await _supabase
            .from('trusted_partner_discounts')
            .select('trusted_partner_id, deal_category, offers_delivery')
            .inFilter('trusted_partner_id', ownerIds)
            .eq('is_active', true),
      );

      final categoryCounts = <String, int>{};
      final allCounts = <String, int>{};
      final categoryDelivers = <String, bool>{};
      final anyDelivers = <String, bool>{};
      for (final deal in deals) {
        final ownerId = deal['trusted_partner_id'] as String?;
        if (ownerId == null) continue;
        final delivers = (deal['offers_delivery'] as bool?) ?? false;
        allCounts[ownerId] = (allCounts[ownerId] ?? 0) + 1;
        if (delivers) anyDelivers[ownerId] = true;
        if (deal['deal_category'] == category) {
          categoryCounts[ownerId] = (categoryCounts[ownerId] ?? 0) + 1;
          if (delivers) categoryDelivers[ownerId] = true;
        }
      }

      final partners = <Map<String, dynamic>>[];
      for (final business in businesses) {
        final ownerId = business['owner_member_id'] as String?;
        if (ownerId == null) continue;
        final categoryCount = categoryCounts[ownerId] ?? 0;
        final count = businessCategory != null
            ? (allCounts[ownerId] ?? 0)
            : categoryCount > 0
            ? categoryCount
            : (allCounts[ownerId] ?? 0);
        if (count == 0) continue;
        partners.add({
          ...business,
          'deal_count': count,
          'offers_delivery': businessCategory != null
              ? (anyDelivers[ownerId] ?? false)
              : categoryCount > 0
              ? (categoryDelivers[ownerId] ?? false)
              : (anyDelivers[ownerId] ?? false),
        });
      }

      partners.sort(
        (a, b) => ((a['name'] as String?) ?? '').toLowerCase().compareTo(
          ((b['name'] as String?) ?? '').toLowerCase(),
        ),
      );

      _logger.i('🔎 Found ${partners.length} $logLabel partners');
      return partners;
    } catch (e) {
      _logger.e('Failed to load $logLabel partners: $e');
      return [];
    }
  }

  /// Trusted partners in the Fresh & Local produce category.
  Future<List<Map<String, dynamic>>> getFreshProducePartners({
    String? city,
  }) => _getCategoryPartners(
    category: kFreshLocalCategory,
    flagColumn: 'sells_fresh_produce',
    logLabel: 'fresh produce',
    city: city,
  );

  /// Trusted partners in the Local Sips locally produced alcohol category.
  Future<List<Map<String, dynamic>>> getLocalSipsPartners({String? city}) =>
      _getCategoryPartners(
        category: kLocalSipsCategory,
        flagColumn: 'sells_alcohol',
        logLabel: 'local sips',
        city: city,
      );

  /// Trusted partners in the Locally Active sport/fitness category.
  Future<List<Map<String, dynamic>>> getLocallyActivePartners({String? city}) =>
      _getCategoryPartners(
        category: kLocallyActiveCategory,
        flagColumn: 'offers_sports_activities',
        logLabel: 'locally active',
        city: city,
      );

  /// Food & Beverage and Restaurant businesses with at least one active deal.
  Future<List<Map<String, dynamic>>> getLocalEatsPartners({String? city}) =>
      _getCategoryPartners(
        category: kLocalEatsCategory,
        businessCategories: kLocalEatsBusinessCategories,
        logLabel: 'local eats',
        city: city,
      );

  /// Lightweight check used to decide whether to surface the Fresh & Local
  /// entry point on the member home screen.
  Future<bool> hasFreshProducePartners({String? city}) async {
    final partners = await getFreshProducePartners(city: city);
    return partners.isNotEmpty;
  }

  /// Drives a category entry banner: whether to show it at all, and how many
  /// qualifying deals were added since [since].
  Future<FreshLocalSummary> _getCategorySummary({
    required String category,
    required List<Map<String, dynamic>> partners,
    DateTime? since,
    bool countAllPartnerDeals = false,
  }) async {
    if (partners.isEmpty) return const FreshLocalSummary();

    final partnerCount = partners.length;
    var dealCount = 0;
    for (final partner in partners) {
      dealCount += (partner['deal_count'] as int?) ?? 0;
    }

    if (since == null) {
      return FreshLocalSummary(
        hasPartners: true,
        partnerCount: partnerCount,
        dealCount: dealCount,
      );
    }

    try {
      final ownerIds = partners
          .map((p) => p['owner_member_id'] as String?)
          .whereType<String>()
          .toList();
      if (ownerIds.isEmpty) {
        return FreshLocalSummary(
          hasPartners: true,
          partnerCount: partnerCount,
          dealCount: dealCount,
        );
      }

      var query = _supabase
          .from('trusted_partner_discounts')
          .select('id')
          .inFilter('trusted_partner_id', ownerIds)
          .eq('is_active', true);
      if (!countAllPartnerDeals) query = query.eq('deal_category', category);
      final rows = await query.gt(
        'created_at',
        since.toUtc().toIso8601String(),
      ) as List;

      return FreshLocalSummary(
        hasPartners: true,
        newDealCount: rows.length,
        partnerCount: partnerCount,
        dealCount: dealCount,
      );
    } catch (e) {
      _logger.e('Failed to count new $category deals: $e');
      return FreshLocalSummary(
        hasPartners: true,
        partnerCount: partnerCount,
        dealCount: dealCount,
      );
    }
  }

  Future<FreshLocalSummary> getFreshLocalSummary({
    String? city,
    DateTime? since,
  }) async => _getCategorySummary(
    category: kFreshLocalCategory,
    partners: await getFreshProducePartners(city: city),
    since: since,
  );

  Future<FreshLocalSummary> getLocalSipsSummary({
    String? city,
    DateTime? since,
  }) async => _getCategorySummary(
    category: kLocalSipsCategory,
    partners: await getLocalSipsPartners(city: city),
    since: since,
  );

  Future<FreshLocalSummary> getLocallyActiveSummary({
    String? city,
    DateTime? since,
  }) async => _getCategorySummary(
    category: kLocallyActiveCategory,
    partners: await getLocallyActivePartners(city: city),
    since: since,
  );

  Future<FreshLocalSummary> getLocalEatsSummary({
    String? city,
    DateTime? since,
  }) async => _getCategorySummary(
    category: kLocalEatsCategory,
    partners: await getLocalEatsPartners(city: city),
    since: since,
    countAllPartnerDeals: true,
  );

  Future<List<Discount>> getNearbyDeals(
    String currentCity, [
    List<String>? nearbyAreas,
  ]) async {
    try {
      final cities = [currentCity];
      if (nearbyAreas != null) {
        cities.addAll(nearbyAreas);
      }

      final response = await _supabase
          .from('trusted_partner_discounts')
          .select()
          .inFilter('city', cities)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      _logger.i('🏙️ Found ${response.length} deals in ${cities.join(", ")}');
      return response.map((json) => Discount.fromJson(json)).toList();
    } catch (e) {
      _logger.e('Failed to load nearby deals: $e');
      throw Exception('Failed to load nearby deals: $e');
    }
  }

  Future<Discount> createDiscount({
    required String trustedPartnerId,
    required String name,
    required String description,
    required String itemName,
    required double itemPrice,
    required double percentage,
    double? fixedAmount,
    String dealType = 'standard',
    Map<String, dynamic>? customData,
    bool requiresManualPrice = false,
    bool isWeightBased = false,
    bool isBillDiscount = false,
    bool isOnceOff = false,
    Map<String, dynamic>? billDiscountData,
    String? imageUrl,
    Map<String, dynamic>? scheduleData,
    String dealCategory = 'Other',
    bool offersDelivery = false,
    String? city,
  }) async {
    try {
      // CRITICAL: Get business_id for this trusted partner
      // This is required for receipt generation
      final businessResponse = await _supabase
          .from('businesses')
          .select('id, city')
          .eq('owner_member_id', trustedPartnerId)
          .maybeSingle();

      if (businessResponse == null) {
        throw Exception(
          'No business found for trusted partner. Please create a business profile first.',
        );
      }

      final businessId = businessResponse['id'] as String;
      // Use provided city or fallback to business city
      final dealCity = city ?? businessResponse['city'] as String?;

      _logger.i(
        'Creating discount for business: $businessId in city: $dealCity',
      );

      if (kDebugMode)
        print('📝 Creating discount with imageUrl: ${imageUrl ?? "NULL"}');

      final response = await _supabase
          .from('trusted_partner_discounts')
          .insert({
            'trusted_partner_id': trustedPartnerId,
            'business_id': businessId, // CRITICAL: Include business_id
            'name': name,
            'description': description,
            'item_name': itemName,
            'item_price': itemPrice,
            'percentage': percentage,
            'fixed_amount': fixedAmount,
            'deal_type': dealType,
            'custom_data': customData,
            'requires_manual_price': requiresManualPrice,
            'is_active': true,
            'is_weight_based': isWeightBased,
            'is_bill_discount': isBillDiscount,
            'is_once_off': isOnceOff,
            'bill_discount_data': billDiscountData,
            'image_url': imageUrl,
            'schedule_data': scheduleData,
            'deal_category': dealCategory,
            'offers_delivery': offersDelivery,
            'city': dealCity,
          })
          .select()
          .single();

      if (kDebugMode)
        print(
          '✅ Discount created, returned imageUrl: ${response['image_url']}',
        );

      return Discount.fromJson(response);
    } catch (e) {
      throw Exception('Failed to create discount: $e');
    }
  }

  Future<void> updateDiscount(
    String discountId, {
    String? name,
    String? description,
    String? itemName,
    double? itemPrice,
    double? percentage,
    double? fixedAmount,
    String? dealType,
    Map<String, dynamic>? customData,
    bool? requiresManualPrice,
    bool? isActive,
    Map<String, dynamic>? billDiscountData,
    String? imageUrl,
    Map<String, dynamic>? scheduleData,
    String? dealCategory,
    bool? offersDelivery,
    bool? isOnceOff,
    bool updateImageUrl =
        false, // Flag to indicate imageUrl should be updated even if null
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (description != null) updates['description'] = description;
      if (itemName != null) updates['item_name'] = itemName;
      if (itemPrice != null) updates['item_price'] = itemPrice;
      if (percentage != null) updates['percentage'] = percentage;
      if (fixedAmount != null) updates['fixed_amount'] = fixedAmount;
      if (dealType != null) updates['deal_type'] = dealType;
      if (customData != null) updates['custom_data'] = customData;
      if (requiresManualPrice != null) {
        updates['requires_manual_price'] = requiresManualPrice;
      }
      if (isActive != null) updates['is_active'] = isActive;
      if (billDiscountData != null) {
        updates['bill_discount_data'] = billDiscountData;
      }
      if (scheduleData != null) {
        updates['schedule_data'] = scheduleData;
      }
      if (dealCategory != null) updates['deal_category'] = dealCategory;
      if (offersDelivery != null) updates['offers_delivery'] = offersDelivery;
      if (isOnceOff != null) updates['is_once_off'] = isOnceOff;
      // Update imageUrl even if null when explicitly requested (for deletion)
      if (updateImageUrl) {
        updates['image_url'] = imageUrl;
        if (kDebugMode)
          print('🖼️ Updating image_url to: ${imageUrl ?? "NULL"}');
      }
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();

      if (kDebugMode) print('📝 Updating discount $discountId with: $updates');

      await _supabase
          .from('trusted_partner_discounts')
          .update(updates)
          .eq('id', discountId);

      if (kDebugMode) print('✅ Discount updated successfully');
    } catch (e) {
      if (kDebugMode) print('❌ Failed to update discount: $e');
      throw Exception('Failed to update discount: $e');
    }
  }

  Future<List<Discount>> getAllTrustedPartnerDiscounts(
    String trustedPartnerId,
  ) async {
    try {
      final response = await _supabase
          .from('trusted_partner_discounts')
          .select()
          .eq('trusted_partner_id', trustedPartnerId)
          .order('created_at', ascending: false);

      final discounts = response
          .map((json) => Discount.fromJson(json))
          .toList();

      // Debug logging
      for (final discount in discounts) {
        _logger.d('Discount ${discount.id}: imageUrl=${discount.imageUrl}');
      }

      return discounts;
    } catch (e) {
      throw Exception('Failed to load discounts: $e');
    }
  }

  Future<void> deleteDiscount(String discountId) async {
    try {
      // Permanently delete the deal from the database
      await _supabase
          .from('trusted_partner_discounts')
          .delete()
          .eq('id', discountId);

      _logger.i('✅ Deleted deal $discountId from database');
    } catch (e) {
      _logger.e('❌ Failed to delete deal: $e');
      throw Exception('Failed to delete deal: $e');
    }
  }

  // ── Static cache for active deals ──
  static List<Map<String, dynamic>>? _cachedActiveDeals;
  static DateTime? _activeDealsCacheTime;
  static const _activeDealsCacheTtl = Duration(minutes: 3);

  /// Invalidate the active-deals cache (call after edits).
  static void invalidateActiveDealsCache() {
    _cachedActiveDeals = null;
    _activeDealsCacheTime = null;
  }

  Future<List<Map<String, dynamic>>> getAllActiveDiscountsWithTrustedPartners({
    bool forceRefresh = false,
  }) async {
    // Return cached data if fresh
    if (!forceRefresh &&
        _cachedActiveDeals != null &&
        _activeDealsCacheTime != null &&
        DateTime.now().difference(_activeDealsCacheTime!) <
            _activeDealsCacheTtl) {
      _logger.d('Returning ${_cachedActiveDeals!.length} cached active deals');
      return _cachedActiveDeals!;
    }

    try {
      _logger.i('Fetching all active discounts from Supabase...');

      // Fetch discounts + businesses in parallel
      final responses = await Future.wait([
        _supabase
            .from('trusted_partner_discounts')
            .select('*')
            .eq('is_active', true)
            .order('created_at', ascending: false),
        _supabase
            .from('businesses')
            .select(
              'id, owner_member_id, name, logo_url, category, city, facebook_handle, instagram_handle, website_url, business_email',
            ),
      ]);

      final discountsResponse = responses[0] as List;
      final allBusinesses = responses[1] as List;

      _logger.i(
        'Fetched ${discountsResponse.length} discounts + ${allBusinesses.length} businesses in parallel',
      );

      if (discountsResponse.isEmpty) {
        _cachedActiveDeals = [];
        _activeDealsCacheTime = DateTime.now();
        return [];
      }

      // Build a single lookup map: owner_member_id → business info
      final bizMap = <String, Map<String, dynamic>>{};
      for (final b in allBusinesses) {
        final ownerId = b['owner_member_id'] as String?;
        if (ownerId != null) bizMap[ownerId] = b;
      }

      // Combine the data in one pass
      final result = discountsResponse.map((discount) {
        final tpId = discount['trusted_partner_id'] as String?;
        final biz = tpId != null ? bizMap[tpId] : null;

        return <String, dynamic>{
          ...discount,
          'business_category': biz?['category'],
          'business_city': biz?['city'],
          'trusted_partners': {
            'business_name': biz?['name'] ?? 'Unknown Trusted Partner',
            'business_id': biz?['id'],
            'logo_url': biz?['logo_url'],
            'category': biz?['category'],
            'city': biz?['city'],
            'facebook_handle': biz?['facebook_handle'],
            'instagram_handle': biz?['instagram_handle'],
            'website_url': biz?['website_url'],
            'business_email': biz?['business_email'],
          },
        };
      }).toList();

      _logger.i(
        'Returning ${result.length} discounts with trusted partner data',
      );

      // Cache the result
      _cachedActiveDeals = result;
      _activeDealsCacheTime = DateTime.now();

      return result;
    } catch (e) {
      throw Exception('Failed to load active discounts: $e');
    }
  }

  Future<Set<String>> getCompletedDealIdsForMember(String memberId) async {
    try {
      final response = await _supabase
          .from('deal_authorizations')
          .select('discount_id, payment_completed_at, status')
          .eq('member_id', memberId)
          .eq('status', 'completed');

      return response
          .map((row) => row['discount_id'] as String?)
          .whereType<String>()
          .toSet();
    } catch (e) {
      throw Exception('Failed to load completed deals for member: $e');
    }
  }

  // Deal Authorization Methods

  Future<DealAuthorization> createDealAuthorization({
    required String memberId,
    required String discountId,
    required String trustedPartnerUserId, // the owner_member_id (user)
    required String businessId, // the businesses.id (UUID)
    required String paymentMethod, // 'in_app' or 'pos'
    required double amount,
    int? quantity,
    double? memberEnteredPrice,
    double? appliedDiscountAmount,
    String? dealType,
    Map<String, dynamic>? dealSnapshot,
    String? notes,
    Map<String, dynamic>? billData,
  }) async {
    try {
      if (kDebugMode) {
        print('🔍 Creating deal authorization:');
        print('   memberId: $memberId');
        print('   discountId: $discountId');
        print('   trustedPartnerUserId: $trustedPartnerUserId');
        print('   businessId: $businessId (length: ${businessId.length})');
        print('   businessId isNotEmpty: ${businessId.isNotEmpty}');
        print(
          '   businessId matches UUID pattern: ${RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$').hasMatch(businessId)}',
        );
        print('   paymentMethod: $paymentMethod');
        print('   amount: $amount');
      }

      // Validate businessId format
      if (businessId.isEmpty) {
        throw Exception('businessId cannot be empty');
      }

      final insertData = {
        'member_id': memberId,
        'discount_id': discountId,
        'trusted_partner_id': trustedPartnerUserId,
        'business_id': businessId,
        'payment_method': paymentMethod,
        'amount': amount,
        'quantity': quantity,
        'member_entered_price': memberEnteredPrice,
        'applied_discount_amount': appliedDiscountAmount,
        'deal_type': dealType,
        'deal_snapshot': dealSnapshot,
        'status': 'pending',
        'notes': notes,
        if (billData != null) 'bill_data': billData,
      };

      if (kDebugMode) {
        print('🔍 Insert data: $insertData');
      }

      final response = await _supabase
          .from('deal_authorizations')
          .insert(insertData)
          .select()
          .single();

      if (kDebugMode) {
        print('✅ Deal authorization created successfully: ${response['id']}');
      }

      return DealAuthorization.fromJson(response);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Deal authorization creation failed: $e');
        print('Error type: ${e.runtimeType}');
      }
      throw Exception('Failed to create deal authorization: $e');
    }
  }

  Future<List<DealAuthorization>> getMemberDealAuthorizations(
    String memberId,
  ) async {
    try {
      final response = await _supabase
          .from('deal_authorizations')
          .select('''
            *,
            trusted_partner_discounts (
              id,
              trusted_partner_id,
              name,
              description,
              item_name,
              item_price,
              percentage,
              fixed_amount,
              deal_type,
              is_active,
              is_weight_based,
              is_bill_discount,
              is_once_off,
              image_url,
              deal_category,
              city,
              created_at,
              updated_at,
              businesses (
                name,
                owner_member_id
              )
            )
          ''')
          .eq('member_id', memberId)
          .order('created_at', ascending: false);

      return response.map((json) => DealAuthorization.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load member deal authorizations: $e');
    }
  }

  Future<List<DealAuthorization>> getTrustedPartnerDealAuthorizations(
    String trustedPartnerUserId,
  ) async {
    try {
      // First, get the business ID for this trusted partner user
      final businessResponse = await _supabase
          .from('businesses')
          .select('id')
          .eq('owner_member_id', trustedPartnerUserId)
          .maybeSingle();

      if (businessResponse == null) {
        // No business found for this user, return empty list
        return [];
      }

      final businessId = businessResponse['id'] as String?;

      if (businessId == null) {
        throw Exception('Business ID is null for trusted partner');
      }

      // Now get deal authorizations for this business
      final response = await _supabase
          .from('deal_authorizations')
          .select('''
            *,
            trusted_partner_discounts (
              id,
              trusted_partner_id,
              business_id,
              name,
              description,
              item_name,
              item_price,
              percentage,
              fixed_amount,
              is_active,
              created_at,
              updated_at
            ),
            profiles!deal_authorizations_member_id_fkey (
              id,
              name,
              surname,
              email,
              created_at,
              updated_at
            )
          ''')
          .eq('business_id', businessId)
          .order('created_at', ascending: false);

      // Parse each record with detailed error handling
      final List<DealAuthorization> authorizations = [];
      final responseList = response as List;
      _logger.i(
        'Received ${responseList.length} deal authorizations from Supabase',
      );

      for (var i = 0; i < responseList.length; i++) {
        try {
          final json = responseList[i] as Map<String, dynamic>;
          _logger.d(
            'Parsing authorization $i: id=${json['id']}, member_id=${json['member_id']}, business_id=${json['business_id']}, discount_id=${json['discount_id']}',
          );
          final auth = DealAuthorization.fromJson(json);
          authorizations.add(auth);
        } catch (e) {
          _logger.w(
            'Skipping deal authorization at index $i due to parse error: $e',
          );
          _logger.w(
            'Problematic JSON keys: ${(responseList[i] as Map).keys.toList()}',
          );
          _logger.w('id: ${responseList[i]['id']}');
          _logger.w('member_id: ${responseList[i]['member_id']}');
          _logger.w('business_id: ${responseList[i]['business_id']}');
          _logger.w('discount_id: ${responseList[i]['discount_id']}');
          // Skip this record — one bad row should not block the entire list
          continue;
        }
      }
      return authorizations;
    } catch (e) {
      throw Exception('Failed to load trusted partner deal authorizations: $e');
    }
  }

  Future<void> updateDealAuthorizationStatus({
    required String dealId,
    required String status,
    String? rejectionReason,
  }) async {
    const maxRetries = 5;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final now = DateTime.now().toUtc().toIso8601String();
        final updates = <String, dynamic>{'status': status, 'updated_at': now};

        // Set appropriate timestamp based on status change
        if (status == 'approved') {
          updates['approved_at'] = now;
        } else if (status == 'completed') {
          updates['completed_at'] = now;
        }

        if (rejectionReason != null) {
          updates['rejection_reason'] = rejectionReason;
        }

        await _supabase
            .from('deal_authorizations')
            .update(updates)
            .eq('id', dealId);

        _logger.i('✅ Updated deal authorization $dealId to status: $status');
        return; // Success, exit retry loop
      } catch (e) {
        final errorStr = e.toString();
        final isRetryable =
            errorStr.contains('502') ||
            errorStr.contains('500') ||
            errorStr.contains('Bad Gateway') ||
            errorStr.contains('503') ||
            errorStr.contains('403') || // RLS transient issues
            errorStr.contains('timeout');

        if (isRetryable && attempt < maxRetries) {
          final backoffMs = (attempt * 500) + (500 * (attempt - 1));
          _logger.w(
            '⚠️ Attempt $attempt failed with error, retrying in ${backoffMs}ms: $e',
          );
          await Future.delayed(Duration(milliseconds: backoffMs));
          continue;
        }

        _logger.e(
          '❌ Failed to update deal authorization status after $maxRetries attempts: $e',
        );
        throw Exception('Failed to update deal authorization status: $e');
      }
    }
  }

  Future<void> deleteDealAuthorization(String dealAuthorizationId) async {
    try {
      await _supabase
          .from('deal_authorizations')
          .delete()
          .eq('id', dealAuthorizationId);

      _logger.i('✅ Deleted deal authorization $dealAuthorizationId');
    } catch (e) {
      _logger.e('❌ Failed to delete deal authorization: $e');
      throw Exception('Failed to delete deal authorization: $e');
    }
  }

  Future<VirtualReceipt> createVirtualReceipt({
    required String dealAuthorizationId,
    required String receiptNumber,
    required Map<String, dynamic> receiptData,
    required String qrCode,
  }) async {
    try {
      final response = await _supabase
          .from('virtual_receipts')
          .insert({
            'deal_authorization_id': dealAuthorizationId,
            'receipt_number': receiptNumber,
            'receipt_data': receiptData,
            'qr_code': qrCode,
          })
          .select()
          .single();

      return VirtualReceipt.fromJson(response);
    } catch (e) {
      throw Exception('Failed to create virtual receipt: $e');
    }
  }

  Future<List<VirtualReceipt>> getVirtualReceipts(
    String dealAuthorizationId,
  ) async {
    try {
      final response = await _supabase
          .from('virtual_receipts')
          .select()
          .eq('deal_authorization_id', dealAuthorizationId)
          .order('created_at', ascending: false);

      return response.map((json) => VirtualReceipt.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load virtual receipts: $e');
    }
  }

  Future<MemberReceipt> saveReceiptToMemberBook({
    required String memberId,
    required String virtualReceiptId,
    required String receiptNumber,
    required String businessName,
    required double amount,
    required DateTime transactionDate,
  }) async {
    try {
      final response = await _supabase
          .from('member_receipts')
          .insert({
            'member_id': memberId,
            'virtual_receipt_id': virtualReceiptId,
            'receipt_number': receiptNumber,
            'business_name': businessName,
            'amount': amount,
            'transaction_date': transactionDate.toIso8601String(),
            'status': 'saved',
          })
          .select()
          .single();

      return MemberReceipt.fromJson(response);
    } catch (e) {
      throw Exception('Failed to save receipt to member book: $e');
    }
  }

  Future<List<MemberReceipt>> getMemberReceiptBook(String memberId) async {
    try {
      final response = await _supabase
          .from('member_receipts')
          .select()
          .eq('member_id', memberId)
          .order('created_at', ascending: false);

      return response.map((json) => MemberReceipt.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load member receipt book: $e');
    }
  }

  Future<List<VirtualReceipt>> getVirtualReceiptsForDeal(
    String dealAuthorizationId,
  ) async {
    try {
      final response = await _supabase
          .from('virtual_receipts')
          .select()
          .eq('deal_authorization_id', dealAuthorizationId)
          .order('created_at', ascending: false);

      return response.map((json) => VirtualReceipt.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load virtual receipts for deal: $e');
    }
  }

  Future<NotificationModel> createNotification({
    required String userId,
    required String title,
    required String message,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    try {
      // Log current session and token
      final session = _supabase.auth.currentSession;
      final token = session?.accessToken;
      if (kDebugMode) {
        print(
          '[DEBUG] Supabase session: '
          '${session != null ? session.toJson() : 'null'}',
        );
      }
      if (kDebugMode) {
        print('[DEBUG] Supabase token: $token');
      }
      if (session == null || token == null) {
        throw Exception(
          'No Supabase session/token found. User is not authenticated.',
        );
      }

      // Use SECURITY DEFINER function to bypass RLS
      // This function returns the full notification record, avoiding SELECT RLS issues
      final result = await _supabase.rpc(
        'create_notification_bypass_rls',
        params: {
          'p_user_id': userId,
          'p_title': title,
          'p_message': message,
          'p_type': type,
          'p_data': data ?? {},
        },
      );

      // The function returns a list with one record
      final notificationData = (result as List).first as Map<String, dynamic>;

      return NotificationModel.fromJson(notificationData);
    } catch (e) {
      if (kDebugMode) {
        print('[ERROR] Failed to create notification: $e');
      }
      throw Exception('Failed to create notification: $e');
    }
  }

  Future<List<NotificationModel>> getUserNotifications(String userId) async {
    try {
      final response = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return response.map((json) => NotificationModel.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load user notifications: $e');
    }
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (e) {
      throw Exception('Failed to mark notification as read: $e');
    }
  }

  // TEMPORARY FIX: Recreate the missing SELECT policy for discounts
  Future<void> fixDiscountVisibility() async {
    try {
      // Try to execute a simple query that should work with the current policy
      // If it fails, the policy is missing
      final testQuery = await _supabase
          .from('trusted_partner_discounts')
          .select('id')
          .limit(1);

      if (testQuery.isEmpty) {
        // If we get here, the policy exists but there might be no data
        if (kDebugMode) {
          print('Policy exists but no discounts found');
        }
      }

      if (kDebugMode) {
        print(
          'Discount visibility test successful: ${testQuery.length} records accessible',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Discount visibility test failed: $e');
      }
      // This suggests the SELECT policy is missing
      throw Exception(
        'Discount visibility policy is missing. Please run the SQL fix manually.',
      );
    }
  }

  // Test function to check if notification bypass function exists
  Future<bool> testNotificationFunction() async {
    try {
      // Try to call the function with test data
      final result = await _supabase.rpc(
        'create_notification_bypass_rls',
        params: {
          'p_user_id': '00000000-0000-0000-0000-000000000000', // dummy UUID
          'p_title': 'Test Function',
          'p_message': 'Testing if function exists',
          'p_type': 'test',
          'p_data': {'test': true},
        },
      );

      if (kDebugMode) {
        print('[TEST] Notification function exists and returned: $result');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('[TEST] Notification function test failed: $e');
      }
      return false;
    }
  }

  Future<void> debugDatabaseState(String trustedPartnerUserId) async {
    try {
      if (kDebugMode) {
        print('DEBUG: Checking database state for user $trustedPartnerUserId');
      }

      // Get business ID
      final businessResponse = await _supabase
          .from('businesses')
          .select('id')
          .eq('owner_member_id', trustedPartnerUserId)
          .maybeSingle();

      if (businessResponse == null) {
        if (kDebugMode) {
          print('DEBUG: No business found for user $trustedPartnerUserId');
        }
        return;
      }

      final businessId = businessResponse['id'] as String;
      if (kDebugMode) {
        print('DEBUG: Found business ID: $businessId');
      }

      // Check all deal authorizations for this business
      final allAuths = await _supabase
          .from('deal_authorizations')
          .select('id, status, created_at')
          .eq('business_id', businessId);

      if (kDebugMode) {
        print('DEBUG: Total deal authorizations: ${allAuths.length}');
      }
      for (final auth in allAuths) {
        if (kDebugMode) {
          print(
            'DEBUG: Auth ${auth['id']} - Status: ${auth['status']} - Created: ${auth['created_at']}',
          );
        }
      }

      // Check pending authorizations
      final pendingAuths = await _supabase
          .from('deal_authorizations')
          .select('id, status, created_at')
          .eq('business_id', businessId)
          .eq('status', 'pending');

      if (kDebugMode) {
        print('DEBUG: Pending deal authorizations: ${pendingAuths.length}');
      }

      // Check notifications for this user
      final notifications = await _supabase
          .from('notifications')
          .select('id, type, data, created_at')
          .eq('user_id', trustedPartnerUserId);

      if (kDebugMode) {
        print('DEBUG: Total notifications for user: ${notifications.length}');
      }
      for (final notif in notifications) {
        if (kDebugMode) {
          print(
            'DEBUG: Notification ${notif['id']} - Type: ${notif['type']} - Data: ${notif['data']}',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('DEBUG: Error checking database state: $e');
      }
    }
  }

  Future<void> createNotificationsForExistingPendingAuthorizations(
    String trustedPartnerUserId,
  ) async {
    try {
      _logger.i(
        'Creating notifications for existing pending authorizations for user: $trustedPartnerUserId',
      );

      // Get business ID for this trusted partner
      final businessResponse = await _supabase
          .from('businesses')
          .select('id')
          .eq('owner_member_id', trustedPartnerUserId)
          .maybeSingle();

      if (businessResponse == null) {
        _logger.w(
          'No business found for trusted partner $trustedPartnerUserId',
        );
        if (kDebugMode) {
          print('BACKFILL: No business found for user $trustedPartnerUserId');
        }
        return;
      }

      final businessId = businessResponse['id'] as String;
      _logger.i('Found business ID: $businessId');
      if (kDebugMode) {
        print('BACKFILL: Found business ID: $businessId');
      }

      // Find pending deal authorizations that don't have notifications
      final pendingAuthsResponse = await _supabase
          .from('deal_authorizations')
          .select('id, member_id, amount, created_at')
          .eq('business_id', businessId)
          .eq('status', 'pending');

      _logger.i('Found ${pendingAuthsResponse.length} pending authorizations');
      if (kDebugMode) {
        print(
          'BACKFILL: Found ${pendingAuthsResponse.length} pending authorizations for business $businessId',
        );
      }

      for (final auth in pendingAuthsResponse) {
        final authId = auth['id'] as String;
        final memberId = auth['member_id'] as String;
        final amount = auth['amount'] as double?;

        if (kDebugMode) {
          print('BACKFILL: Checking notification for auth $authId');
        }

        // Check if notification already exists
        final existingNotification = await _supabase
            .from('notifications')
            .select('id')
            .eq('user_id', trustedPartnerUserId)
            .eq('type', 'deal_request')
            .filter('data->>deal_authorization_id', 'eq', authId)
            .maybeSingle();

        if (existingNotification == null) {
          if (kDebugMode) {
            print(
              'BACKFILL: No existing notification found, creating new one for auth $authId',
            );
          }
          try {
            // Try direct insert first (bypass RLS)
            final notificationResponse = await _supabase
                .from('notifications')
                .insert({
                  'user_id': trustedPartnerUserId,
                  'title': 'New Deal Authorization Request',
                  'message':
                      'A member has requested authorization for a deal worth R${amount?.toStringAsFixed(2) ?? 'N/A'}',
                  'type': 'deal_request',
                  'data': {
                    'deal_authorization_id': authId,
                    'member_id': memberId,
                    'amount': amount,
                  },
                  'is_read': false,
                })
                .select()
                .single();

            if (kDebugMode) {
              print(
                'BACKFILL: Direct insert successful: ${notificationResponse['id']}',
              );
            }
          } catch (directInsertError) {
            if (kDebugMode) {
              print('BACKFILL: Direct insert failed: $directInsertError');
            }
            // Fallback to RPC function
            try {
              await createNotification(
                userId: trustedPartnerUserId,
                title: 'New Deal Authorization Request',
                message:
                    'A member has requested authorization for a deal worth R${amount?.toStringAsFixed(2) ?? 'N/A'}',
                type: 'deal_request',
                data: {
                  'deal_authorization_id': authId,
                  'member_id': memberId,
                  'amount': amount,
                },
              );
              if (kDebugMode) {
                print('BACKFILL: RPC fallback successful');
              }
            } catch (rpcError) {
              if (kDebugMode) {
                print('BACKFILL: RPC fallback also failed: $rpcError');
              }
            }
          }

          _logger.i('Created notification for deal authorization $authId');
          if (kDebugMode) {
            print(
              'BACKFILL: Successfully created notification for auth $authId',
            );
          }
        } else {
          _logger.d(
            'Notification already exists for deal authorization $authId',
          );
          if (kDebugMode) {
            print('BACKFILL: Notification already exists for auth $authId');
          }
        }
      }

      _logger.i(
        'Finished creating notifications for existing pending authorizations',
      );
      if (kDebugMode) {
        print('BACKFILL: Finished backfill process');
      }
    } catch (e) {
      _logger.e(
        'Failed to create notifications for existing pending authorizations: $e',
      );
      // Don't throw - this is a background operation
    }
  }
}
