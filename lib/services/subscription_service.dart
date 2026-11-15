import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'paystack_service.dart';
import 'subscription_billing_service.dart';

class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  final Logger _logger = Logger();

  static DateTime oneCalendarMonthFrom(DateTime from) =>
      addCalendarMonths(from, 1);

  static DateTime addCalendarMonths(DateTime from, int months) {
    var year = from.year;
    var month = from.month + months;
    while (month > 12) {
      month -= 12;
      year++;
    }
    while (month < 1) {
      month += 12;
      year--;
    }
    final maxDay = DateTime(year, month + 1, 0).day;
    final day = from.day > maxDay ? maxDay : from.day;
    return DateTime(
      year,
      month,
      day,
      from.hour,
      from.minute,
      from.second,
      from.millisecond,
      from.microsecond,
    );
  }

  Future<bool> processManualPayment({
    required String userId,
    required String planType,
    String? paystackSubscriptionCode,
    int renewalAmountCents = 9900,
    String? paymentReference,
  }) =>
      SubscriptionBillingService().confirm(userId, reference: paymentReference);

  Future<bool> activateIntroCampaignSubscription({
    required String userId,
    required String promotionId,
    required String participantId,
    required int freeMonths,
    required int initialChargeCents,
    required int renewalChargeCents,
    String? introChargeReference,
  }) => SubscriptionBillingService().confirm(
    userId,
    reference: introChargeReference,
  );

  Future<Map<String, dynamic>?> getSubscriptionStatus(String userId) async {
    try {
      final result = await _client.rpc(
        'get_subscription_status',
        params: {'p_user_id': userId},
      );
      if (result is Map<String, dynamic>) {
        return {
          ...result,
          'status': result['subscription_status'],
          'current_period_end': result['subscription_end_date'],
        };
      }
    } on PostgrestException catch (error) {
      _logger.w(
        'Subscription status RPC failed; reading membership directly',
        error: error,
      );
    }
    final rows = await _client
        .from('subscriptions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) {
      final profile = await _client
          .from('profiles')
          .select('subscription')
          .eq('id', userId)
          .maybeSingle();
      if (profile?['subscription'] != 'active') return null;
      return {
        'status': 'active',
        'subscription_status': 'active',
        'source': 'profiles.subscription',
      };
    }
    final sub = Map<String, dynamic>.from(rows.first);
    final qr = await _client
        .from('user_qr_codes')
        .select('id')
        .eq('user_id', userId)
        .eq('is_active', true)
        .gte('expires_at', DateTime.now().toIso8601String())
        .limit(1);
    sub['has_active_qr'] = qr.isNotEmpty;
    sub['subscription_status'] = sub['status'];
    final end = DateTime.parse(sub['current_period_end'] as String);
    sub['days_until_renewal'] = end.isAfter(DateTime.now())
        ? end.difference(DateTime.now()).inDays
        : 0;
    return sub;
  }

  Future<Map<String, dynamic>?> getUserQrCode(String userId) async {
    final rows = await _client
        .from('user_qr_codes')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : rows.first;
  }

  /// App startup is read-only: only the server scheduler submits auto-renewals.
  Future<bool> checkAndHandleExpiredSubscription(String userId) async {
    final subscription = await getSubscriptionStatus(userId);
    final rawEnd = subscription?['current_period_end'] as String?;
    if (rawEnd == null) return false;
    final end = DateTime.parse(rawEnd);
    if (subscription?['auto_renew'] == true &&
        DateTime.now().difference(end) < const Duration(hours: 36)) {
      return false;
    }
    return end.isBefore(DateTime.now());
  }

  Duration getTimeUntilNextPayment(DateTime subscriptionEndDate) {
    final now = DateTime.now();
    return subscriptionEndDate.isBefore(now)
        ? Duration.zero
        : subscriptionEndDate.difference(now);
  }

  /// Retained for older callers, but never submits a debit from the app.
  Future<bool> processSubscriptionRenewal(String userId) async {
    _logger.i('Automatic membership renewal is owned by the server scheduler');
    return false;
  }

  Future<Map<String, dynamic>?> getPrimaryPaymentMethodDetails(
    String userId,
  ) async {
    final service = PaystackService();
    final primary = await service.getPrimaryPaymentMethod(userId);
    if (primary == null) return null;
    for (final method in await service.getSavedPaymentMethods(userId)) {
      if (method['id'] == primary || method['authorization_code'] == primary) {
        return method;
      }
    }
    return null;
  }
}
