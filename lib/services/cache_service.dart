import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

/// Cache service for deals and trusted partners
/// Provides instant data availability with configurable TTL
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  static CacheService get instance => _instance;

  final Logger _logger = Logger();

  // In-memory caches
  Map<String, dynamic>? _dealsCache;
  DateTime? _dealsCacheTime;

  Map<String, dynamic>? _trustedPartnersCache;
  DateTime? _trustedPartnersCacheTime;

  Map<String, Map<String, dynamic>>? _memberPartnersCache;
  Map<String, DateTime>? _memberPartnersCacheTime;

  // Cache duration (5 minutes for instant feel with fresh data)
  static const Duration _cacheDuration = Duration(minutes: 5);

  // SharedPreferences keys
  static const String _dealsKey = 'cached_deals';
  static const String _dealsTimeKey = 'cached_deals_time';
  static const String _partnersKey = 'cached_partners';
  static const String _partnersTimeKey = 'cached_partners_time';

  /// Initialize cache from persistent storage
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load deals cache
      final dealsJson = prefs.getString(_dealsKey);
      final dealsTimeStr = prefs.getString(_dealsTimeKey);
      if (dealsJson != null && dealsTimeStr != null) {
        final dealsTime = DateTime.parse(dealsTimeStr);
        if (DateTime.now().difference(dealsTime) < _cacheDuration) {
          _dealsCache = json.decode(dealsJson);
          _dealsCacheTime = dealsTime;
          _logger.i(
            '✅ Loaded deals cache from storage (${_dealsCache!['deals']?.length ?? 0} deals)',
          );
        }
      }

      // Load partners cache
      final partnersJson = prefs.getString(_partnersKey);
      final partnersTimeStr = prefs.getString(_partnersTimeKey);
      if (partnersJson != null && partnersTimeStr != null) {
        final partnersTime = DateTime.parse(partnersTimeStr);
        if (DateTime.now().difference(partnersTime) < _cacheDuration) {
          _trustedPartnersCache = json.decode(partnersJson);
          _trustedPartnersCacheTime = partnersTime;
          _logger.i(
            '✅ Loaded partners cache from storage (${_trustedPartnersCache!['partners']?.length ?? 0} partners)',
          );
        }
      }
    } catch (e) {
      _logger.e('❌ Error loading cache from storage: $e');
    }
  }

  /// Get cached deals if available and not expired
  Map<String, dynamic>? getCachedDeals() {
    if (_dealsCache == null || _dealsCacheTime == null) {
      return null;
    }

    final age = DateTime.now().difference(_dealsCacheTime!);
    if (age > _cacheDuration) {
      _logger.d('⏰ Deals cache expired (${age.inMinutes}m old)');
      _dealsCache = null;
      _dealsCacheTime = null;
      return null;
    }

    _logger.d('⚡ Returning cached deals (${age.inSeconds}s old)');
    return _dealsCache;
  }

  /// Cache deals data
  Future<void> cacheDeals(List<Map<String, dynamic>> deals) async {
    try {
      final cacheData = {
        'deals': deals,
        'timestamp': DateTime.now().toIso8601String(),
      };

      _dealsCache = cacheData;
      _dealsCacheTime = DateTime.now();

      // Persist to storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dealsKey, json.encode(cacheData));
      await prefs.setString(_dealsTimeKey, _dealsCacheTime!.toIso8601String());

      _logger.i('💾 Cached ${deals.length} deals');
    } catch (e) {
      _logger.e('❌ Error caching deals: $e');
    }
  }

  /// Get cached trusted partners if available and not expired
  Map<String, dynamic>? getCachedTrustedPartners() {
    if (_trustedPartnersCache == null || _trustedPartnersCacheTime == null) {
      return null;
    }

    final age = DateTime.now().difference(_trustedPartnersCacheTime!);
    if (age > _cacheDuration) {
      _logger.d('⏰ Partners cache expired (${age.inMinutes}m old)');
      _trustedPartnersCache = null;
      _trustedPartnersCacheTime = null;
      return null;
    }

    _logger.d('⚡ Returning cached partners (${age.inSeconds}s old)');
    return _trustedPartnersCache;
  }

  /// Cache trusted partners data
  Future<void> cacheTrustedPartners(List<Map<String, dynamic>> partners) async {
    try {
      final cacheData = {
        'partners': partners,
        'timestamp': DateTime.now().toIso8601String(),
      };

      _trustedPartnersCache = cacheData;
      _trustedPartnersCacheTime = DateTime.now();

      // Persist to storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_partnersKey, json.encode(cacheData));
      await prefs.setString(
        _partnersTimeKey,
        _trustedPartnersCacheTime!.toIso8601String(),
      );

      _logger.i('💾 Cached ${partners.length} trusted partners');
    } catch (e) {
      _logger.e('❌ Error caching partners: $e');
    }
  }

  /// Get cached member partners (for member profile page)
  List<Map<String, dynamic>>? getCachedMemberPartners(String memberId) {
    if (_memberPartnersCache == null || _memberPartnersCacheTime == null) {
      return null;
    }

    final cached = _memberPartnersCache![memberId];
    final cacheTime = _memberPartnersCacheTime![memberId];

    if (cached == null || cacheTime == null) {
      return null;
    }

    final age = DateTime.now().difference(cacheTime);
    if (age > _cacheDuration) {
      _logger.d(
        '⏰ Member partners cache expired for $memberId (${age.inMinutes}m old)',
      );
      _memberPartnersCache!.remove(memberId);
      _memberPartnersCacheTime!.remove(memberId);
      return null;
    }

    _logger.d(
      '⚡ Returning cached member partners for $memberId (${age.inSeconds}s old)',
    );
    return (cached['partners'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  /// Cache member partners
  void cacheMemberPartners(
    String memberId,
    List<Map<String, dynamic>> partners,
  ) {
    try {
      _memberPartnersCache ??= {};
      _memberPartnersCacheTime ??= {};

      _memberPartnersCache![memberId] = {
        'partners': partners,
        'timestamp': DateTime.now().toIso8601String(),
      };
      _memberPartnersCacheTime![memberId] = DateTime.now();

      _logger.i('💾 Cached ${partners.length} partners for member $memberId');
    } catch (e) {
      _logger.e('❌ Error caching member partners: $e');
    }
  }

  /// Clear all caches
  Future<void> clearAll() async {
    _dealsCache = null;
    _dealsCacheTime = null;
    _trustedPartnersCache = null;
    _trustedPartnersCacheTime = null;
    _memberPartnersCache = null;
    _memberPartnersCacheTime = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dealsKey);
    await prefs.remove(_dealsTimeKey);
    await prefs.remove(_partnersKey);
    await prefs.remove(_partnersTimeKey);

    _logger.i('🧹 All caches cleared');
  }

  /// Clear deals cache
  Future<void> clearDealsCache() async {
    _dealsCache = null;
    _dealsCacheTime = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dealsKey);
    await prefs.remove(_dealsTimeKey);

    _logger.i('🧹 Deals cache cleared');
  }

  /// Clear trusted partners cache
  Future<void> clearPartnersCache() async {
    _trustedPartnersCache = null;
    _trustedPartnersCacheTime = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_partnersKey);
    await prefs.remove(_partnersTimeKey);

    _logger.i('🧹 Partners cache cleared');
  }

  /// Clear member partners cache
  void clearMemberPartnersCache([String? memberId]) {
    if (memberId != null) {
      _memberPartnersCache?.remove(memberId);
      _memberPartnersCacheTime?.remove(memberId);
      _logger.i('🧹 Member partners cache cleared for $memberId');
    } else {
      _memberPartnersCache = null;
      _memberPartnersCacheTime = null;
      _logger.i('🧹 All member partners caches cleared');
    }
  }
}
