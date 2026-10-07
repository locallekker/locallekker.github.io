import 'package:logger/logger.dart';

import '../models/admin_engagement_report.dart';
import 'supabase_service.dart';

class AdminEngagementService {
  static final AdminEngagementService _instance =
      AdminEngagementService._internal();
  factory AdminEngagementService() => _instance;
  AdminEngagementService._internal();

  final Logger _logger = Logger();

  Future<AdminEngagementReport> fetchReport({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!start.isBefore(end)) {
      throw ArgumentError('Report start must be before end');
    }
    try {
      final response = await SupabaseService.instance.client.rpc(
        'get_admin_engagement_report',
        params: {
          'p_start': start.toUtc().toIso8601String(),
          'p_end': end.toUtc().toIso8601String(),
        },
      );
      return AdminEngagementReport.fromMap(
        Map<String, dynamic>.from(response as Map),
      );
    } catch (e, stack) {
      _logger.e(
        'Failed to load admin engagement report',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<void> recordDealOpen(String dealId) async {
    if (SupabaseService.instance.getCurrentUser() == null) return;
    try {
      await SupabaseService.instance.client.rpc(
        'record_deal_detail_view',
        params: {'p_deal_id': dealId},
      );
    } catch (e, stack) {
      // Analytics failures must not interrupt a member's purchase.
      _logger.w(
        'Failed to record deal detail view',
        error: e,
        stackTrace: stack,
      );
    }
  }
}
