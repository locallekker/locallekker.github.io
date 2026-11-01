import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/guest_conversion_report.dart';
import 'supabase_service.dart';

/// Anonymous analytics for members browsing before they sign in.
///
/// Each device gets a random guest id (no personal data). Visits and deal
/// request attempts are recorded against that id, and the id is linked to the
/// member's account once they sign up or sign in so admins can measure
/// conversion. Analytics failures never block browsing or sign-in.
class GuestAnalyticsService {
  static final GuestAnalyticsService _instance =
      GuestAnalyticsService._internal();
  factory GuestAnalyticsService() => _instance;
  GuestAnalyticsService._internal();

  static const String guestIdKey = 'guest_analytics_id';

  final Logger _logger = Logger();
  bool _visitRecorded = false;
  Future<void>? _linking;

  bool get _isGuest => SupabaseService.instance.getCurrentUser() == null;

  @visibleForTesting
  void resetSessionForTesting() => _visitRecorded = false;

  Future<String> _guestId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(guestIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await prefs.setString(guestIdKey, created);
    return created;
  }

  /// Records that a guest is browsing. Sent at most once per app session.
  Future<void> recordVisit() async {
    if (_visitRecorded || !_isGuest) return;
    _visitRecorded = true;
    try {
      await SupabaseService.instance.client.rpc(
        'record_guest_visit',
        params: {'p_guest_id': await _guestId()},
      );
    } catch (e, stack) {
      _visitRecorded = false;
      _logger.w('Failed to record guest visit', error: e, stackTrace: stack);
    }
  }

  /// Records a guest trying to request [dealId] before signing in.
  Future<void> recordDealRequest(String dealId, {double? savings}) async {
    if (dealId.isEmpty || !_isGuest) return;
    try {
      await SupabaseService.instance.client.rpc(
        'record_guest_deal_request',
        params: {
          'p_guest_id': await _guestId(),
          'p_discount_id': dealId,
          'p_potential_savings': savings != null && savings > 0
              ? double.parse(savings.toStringAsFixed(2))
              : null,
        },
      );
    } catch (e, stack) {
      _logger.w(
        'Failed to record guest deal request',
        error: e,
        stackTrace: stack,
      );
    }
  }

  Future<GuestConversionReport> fetchAdminReport({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!start.isBefore(end)) {
      throw ArgumentError('Report start must be before end');
    }
    try {
      final response = await SupabaseService.instance.client.rpc(
        'get_admin_guest_conversion_report',
        params: {
          'p_start': start.toUtc().toIso8601String(),
          'p_end': end.toUtc().toIso8601String(),
        },
      );
      return GuestConversionReport.fromMap(
        Map<String, dynamic>.from(response as Map),
      );
    } catch (e, stack) {
      _logger.e(
        'Failed to load guest conversion report',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Links this device's guest browsing to the signed-in member, then starts
  /// a fresh guest id so a later sign-out is tracked separately.
  Future<void> linkConversion() {
    return _linking ??= _link().whenComplete(() => _linking = null);
  }

  Future<void> _link() async {
    if (_isGuest) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final guestId = prefs.getString(guestIdKey);
      if (guestId == null || guestId.isEmpty) return;
      await SupabaseService.instance.client.rpc(
        'link_guest_conversion',
        params: {'p_guest_id': guestId},
      );
      await prefs.remove(guestIdKey);
      _visitRecorded = false;
    } catch (e, stack) {
      _logger.w(
        'Failed to link guest conversion',
        error: e,
        stackTrace: stack,
      );
    }
  }
}
