import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import 'package:crypto/crypto.dart';

class PaystackWebhookHandler {
  static final PaystackWebhookHandler _instance =
      PaystackWebhookHandler._internal();
  factory PaystackWebhookHandler() => _instance;
  PaystackWebhookHandler._internal();

  final _supabase = Supabase.instance.client;
  final Logger _logger = Logger();

  /// Verify Paystack webhook signature using HMAC SHA512
  bool verifyWebhookSignature(
    String payload,
    String? signature,
    String secretKey,
  ) {
    if (signature == null || signature.isEmpty) {
      _logger.w('PaystackWebhookHandler: No signature provided');
      return false;
    }

    try {
      final hmac = Hmac(sha512, utf8.encode(secretKey));
      final expectedSignature =
          'sha512=${hmac.convert(utf8.encode(payload)).toString()}';

      final isValid = signature == expectedSignature;
      if (!isValid) {
        _logger.w('PaystackWebhookHandler: Signature verification failed');
      }
      return isValid;
    } catch (e) {
      _logger.e('PaystackWebhookHandler: Error verifying signature: $e');
      return false;
    }
  }

  /// Process Paystack webhook
  /// This should be called from your server endpoint that receives Paystack webhooks
  Future<bool> processWebhook(
    Map<String, dynamic> webhookData,
    String? signature,
    String secretKey,
  ) async {
    try {
      // Verify webhook signature
      if (!verifyWebhookSignature(
        jsonEncode(webhookData),
        signature,
        secretKey,
      )) {
        _logger.w('PaystackWebhookHandler: Invalid webhook signature');
        return false;
      }

      _logger.i(
        'PaystackWebhookHandler: Processing webhook: ${webhookData['event']}',
      );

      final event = webhookData['event'];
      final data = webhookData['data'];

      if (data == null) {
        _logger.w('PaystackWebhookHandler: No data in webhook');
        return false;
      }

      switch (event) {
        case 'charge.success':
          return await _handleChargeSuccess(data, webhookData);
        case 'subscription.create':
          return await _handleSubscriptionCreate(data);
        case 'invoice.payment_failed':
          return await _handlePaymentFailed(data);
        case 'subscription.disable':
          return await _handleSubscriptionDisable(data);
        default:
          _logger.w('PaystackWebhookHandler: Unhandled event: $event');
          return true; // Acknowledge unhandled events
      }
    } catch (e) {
      _logger.e('PaystackWebhookHandler: Error processing webhook: $e');
      return false;
    }
  }

  Future<bool> _handleChargeSuccess(
    Map<String, dynamic> data,
    Map<String, dynamic> rawWebhookData,
  ) async {
    try {
      final reference = data['reference'];
      final customer = data['customer'];
      final authorization = data['authorization'];
      final metadata = data['metadata'] ?? {};

      _logger.i(
        'PaystackWebhookHandler: Processing successful charge: $reference',
      );

      // Extract user information from metadata or customer data
      final userId = metadata['user_id'] ?? customer['email'];
      final paymentType = metadata['payment_type'] ?? 'unknown';

      if (userId == null) {
        _logger.w('PaystackWebhookHandler: Missing user ID in charge success');
        return false;
      }

      // Update payment record with status and raw event
      final updateData = {
        'status': 'completed',
        'completed_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'raw_event': rawWebhookData,
      };

      await _supabase
          .from('payments')
          .update(updateData)
          .eq('paystack_reference', reference);

      // Save authorization code to profile if this is a card payment
      if (authorization != null &&
          authorization['authorization_code'] != null) {
        await _saveAuthorizationCodeToProfile(
          userId,
          authorization['authorization_code'],
        );
      }

      if (paymentType == 'subscription') {
        // Update user membership if this is a subscription payment
        final planName = metadata['plan_name'] ?? 'premium';
        await _updateUserMembership(userId, planName);
      }

      _logger.i(
        'PaystackWebhookHandler: Charge success processed for user: $userId',
      );
      return true;
    } catch (e) {
      _logger.e('PaystackWebhookHandler: Error handling charge success: $e');
      return false;
    }
  }

  Future<bool> _handleSubscriptionCreate(Map<String, dynamic> data) async {
    try {
      final subscriptionCode = data['subscription_code'];
      final customer = data['customer'];
      final plan = data['plan'];

      _logger.i(
        'PaystackWebhookHandler: Processing subscription create: $subscriptionCode',
      );

      // Resolve user_id from customer_code or email
      final customerCode = customer?['customer_code'] as String?;
      final customerEmail = customer?['email'] as String?;
      String? userId;

      if (customerCode != null && customerCode.isNotEmpty) {
        final res = await _supabase
            .from('profiles')
            .select('id')
            .eq('paystack_customer_code', customerCode)
            .maybeSingle();
        userId = res?['id'] as String?;
      }

      if (userId == null && customerEmail != null && customerEmail.isNotEmpty) {
        final res = await _supabase
            .from('profiles')
            .select('id')
            .eq('email', customerEmail)
            .maybeSingle();
        userId = res?['id'] as String?;
      }

      if (userId == null) {
        _logger.w('PaystackWebhookHandler: Could not resolve user from customer data');
        return false;
      }

      final planName =
          plan?['name']
              ?.replaceFirst('Local Lekker ', '')
              ?.replaceFirst(' Subscription', '') ??
          'subscription';

      // Save subscription code to existing subscription record
      final existingSub = await _supabase
          .from('subscriptions')
          .select('id, paystack_subscription_code')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existingSub != null && existingSub['paystack_subscription_code'] == null) {
        await _supabase
            .from('subscriptions')
            .update({
              'paystack_subscription_code': subscriptionCode,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', existingSub['id']);
      }

      // Update user membership
      await _updateUserMembership(userId, planName);

      _logger.i(
        'PaystackWebhookHandler: Subscription created for user: $userId',
      );
      return true;
    } catch (e) {
      _logger.e(
        'PaystackWebhookHandler: Error handling subscription create: $e',
      );
      return false;
    }
  }

  Future<bool> _handlePaymentFailed(Map<String, dynamic> data) async {
    try {
      final subscriptionCode = data['subscription_code'];
      _logger.i(
        'PaystackWebhookHandler: Processing payment failed for subscription: $subscriptionCode',
      );

      // Update subscription status
      await _supabase
          .from('subscriptions')
          .update({'status': 'payment_failed'})
          .eq('paystack_subscription_code', subscriptionCode);

      // Could also notify user about failed payment
      _logger.i(
        'PaystackWebhookHandler: Payment failed processed for subscription: $subscriptionCode',
      );
      return true;
    } catch (e) {
      _logger.e('PaystackWebhookHandler: Error handling payment failed: $e');
      return false;
    }
  }

  Future<bool> _handleSubscriptionDisable(Map<String, dynamic> data) async {
    try {
      final subscriptionCode = data['subscription_code'];
      final customer = data['customer'];

      _logger.i(
        'PaystackWebhookHandler: Processing subscription disable: $subscriptionCode',
      );

      final userId = customer['email'];

      // Update subscription status
      await _supabase
          .from('subscriptions')
          .update({'status': 'cancelled'})
          .eq('paystack_subscription_code', subscriptionCode);

      // Downgrade user membership
      await _updateUserMembership(userId, 'free');

      _logger.i(
        'PaystackWebhookHandler: Subscription disabled for user: $userId',
      );
      return true;
    } catch (e) {
      _logger.e(
        'PaystackWebhookHandler: Error handling subscription disable: $e',
      );
      return false;
    }
  }

  Future<void> _saveAuthorizationCodeToProfile(
    String userId,
    String authorizationCode,
  ) async {
    try {
      await _supabase
          .from('profiles')
          .update({
            'paystack_auth_code': authorizationCode,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
      _logger.i(
        'PaystackWebhookHandler: Saved authorization code for user: $userId',
      );
    } catch (e) {
      _logger.e('PaystackWebhookHandler: Error saving authorization code: $e');
    }
  }

  Future<void> _updateUserMembership(String userId, String planName) async {
    try {
      // Map plan names to roles
      final roleMapping = {
        'free': 'free',
        'basic': 'basic',
        'premium': 'premium',
        'business': 'business',
      };

      final role = roleMapping[planName.toLowerCase()] ?? 'free';

      // Update memberships table (upsert in case row doesn't exist yet)
      await _supabase
          .from('memberships')
          .upsert({
            'user_id': userId,
            'role': role,
          });

      _logger.i('PaystackWebhookHandler: Updated user $userId role to $role');
    } catch (e) {
      _logger.e('PaystackWebhookHandler: Error updating user membership: $e');
    }
  }
}
