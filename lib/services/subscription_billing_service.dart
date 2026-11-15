import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'payment_status_service.dart';

class SubscriptionBillingResult {
  const SubscriptionBillingResult({
    required this.state,
    required this.reference,
    this.authorizationUrl,
    this.transaction,
    this.message,
  });

  final String state;
  final String reference;
  final String? authorizationUrl;
  final Map<String, dynamic>? transaction;
  final String? message;
  bool get paid => state == 'paid';
}

class SubscriptionBillingService {
  static final SubscriptionBillingService _instance =
      SubscriptionBillingService._internal();
  factory SubscriptionBillingService() => _instance;
  SubscriptionBillingService._internal();

  final Logger _logger = Logger();

  String? _readFunctionError(dynamic details) {
    if (details is Map) {
      for (final key in ['error', 'message', 'msg']) {
        final value = details[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }

    if (details is String && details.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(details);
        if (decoded is Map) return _readFunctionError(decoded);
      } on FormatException {
        // A non-JSON gateway response is reported with its HTTP status below.
      }
    }
    return null;
  }

  Future<SubscriptionBillingResult> request({
    required String action,
    String? authorizationCode,
    String? cvv,
    String? reference,
    String? promotionId,
    String? participantId,
    bool useCustomerCode = true,
  }) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw StateError('Sign in before making a payment.');
      final response = await client.functions.invoke(
        'subscription-billing',
        body: {
          'action': action,
          'authorization_code': ?authorizationCode,
          'cvv': ?cvv,
          'reference': ?reference,
          'promotion_id': ?promotionId,
          'participant_id': ?participantId,
          'use_customer_code': useCustomerCode,
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic> ||
          data['state'] is! String ||
          data['reference'] is! String) {
        throw StateError(
          'Invalid response from the membership billing service.',
        );
      }
      final result = SubscriptionBillingResult(
        state: data['state'] as String,
        reference: data['reference'] as String,
        authorizationUrl: data['authorization_url'] as String?,
        transaction: data['transaction'] as Map<String, dynamic>?,
        message: data['message'] as String?,
      );
      if (result.paid) {
        await PaymentStatusService().clearPendingTransactionReference(userId);
        await PaymentStatusService().clearPendingPayment(userId);
      } else {
        await PaymentStatusService().savePendingTransactionReference(
          userId: userId,
          reference: result.reference,
          planType: promotionId == null ? 'subscription' : 'promotion_intro',
        );
      }
      return result;
    } on FunctionException catch (error) {
      _logger.e('Membership billing request failed', error: error);
      throw Exception(
        _readFunctionError(error.details) ??
            'Membership payment could not be confirmed (billing service HTTP ${error.status}). Please contact support before retrying.',
      );
    } catch (error) {
      _logger.e('Membership billing request failed', error: error);
      rethrow;
    }
  }

  Future<bool> confirm(String userId, {String? reference}) async {
    if (Supabase.instance.client.auth.currentUser?.id != userId) {
      throw StateError('Payment account does not match the signed-in member.');
    }
    final pending = await PaymentStatusService().getPendingTransactionReference(
      userId,
    );
    final paymentReference = reference ?? pending?['reference'];
    if (paymentReference == null || !paymentReference.startsWith('ll-sub-')) {
      // Old checkout recovery is handled by the legacy webhook, never by client activation.
      final sub = await Supabase.instance.client
          .from('subscriptions')
          .select('status, current_period_end')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return sub?['status'] == 'active' &&
          DateTime.parse(
            sub!['current_period_end'] as String,
          ).isAfter(DateTime.now());
    }
    return (await request(action: 'verify', reference: paymentReference)).paid;
  }
}
