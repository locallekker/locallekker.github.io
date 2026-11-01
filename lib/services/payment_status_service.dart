import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_lekker/services/supabase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

class PaymentStatusService {
  static const String _pendingPlanKey = 'pending_payment_plan';
  static const String _pendingPlanDetailsKey = 'pending_payment_plan_details';
  static const String _memberIdKey = 'pending_payment_member_id';
  static const String _pendingTransactionRefKey = 'pending_transaction_reference';
  static const String _pendingTransactionUserIdKey = 'pending_transaction_user_id';
  static const String _pendingTransactionPlanTypeKey = 'pending_transaction_plan_type';
  final Logger _logger = Logger();

  static final PaymentStatusService _instance =
      PaymentStatusService._internal();
  factory PaymentStatusService() => _instance;
  PaymentStatusService._internal();

  Future<void> savePendingPayment({
    required String memberId,
    required String selectedPlan,
    required Map<String, dynamic> planDetails,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_memberIdKey, memberId);
    await prefs.setString(_pendingPlanKey, selectedPlan);
    await prefs.setString(_pendingPlanDetailsKey, jsonEncode(planDetails));
  }

  Future<Map<String, dynamic>?> getPendingPayment(String memberId) async {
    final prefs = await SharedPreferences.getInstance();
    final storedMemberId = prefs.getString(_memberIdKey);

    if (storedMemberId != memberId) {
      return null; // No pending payment for this member
    }

    final plan = prefs.getString(_pendingPlanKey);
    final planDetailsString = prefs.getString(_pendingPlanDetailsKey);

    if (plan == null || planDetailsString == null) {
      return null;
    }

    try {
      // Parse plan details using JSON
      final planDetails = jsonDecode(planDetailsString) as Map<String, dynamic>;
      return {'selectedPlan': plan, 'planDetails': planDetails};
    } catch (e) {
      // Handle legacy data format or corrupted data
      if (kDebugMode) {

        print(
        'PaymentStatusService.getPendingPayment: Error parsing plan details: $e',
      );

      }
      if (kDebugMode) {

        print('Raw plan details: $planDetailsString');

      }

      // Try to clear corrupted data
      try {
        await clearPendingPayment(memberId);
      } catch (clearError) {
        if (kDebugMode) {

          print(
          'PaymentStatusService.getPendingPayment: Error clearing corrupted data: $clearError',
        );

        }
      }

      return null;
    }
  }

  Future<void> clearPendingPayment(String memberId) async {
    final prefs = await SharedPreferences.getInstance();
    final storedMemberId = prefs.getString(_memberIdKey);

    if (storedMemberId == memberId) {
      await prefs.remove(_memberIdKey);
      await prefs.remove(_pendingPlanKey);
      await prefs.remove(_pendingPlanDetailsKey);
    }
  }

  Future<bool> hasPendingPayment(String memberId) async {
    final pending = await getPendingPayment(memberId);
    return pending != null;
  }

  /// Save the Paystack transaction reference before opening the WebView.
  /// This allows recovery if the app closes before payment success is handled.
  Future<void> savePendingTransactionReference({
    required String userId,
    required String reference,
    required String planType,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingTransactionRefKey, reference);
    await prefs.setString(_pendingTransactionUserIdKey, userId);
    await prefs.setString(_pendingTransactionPlanTypeKey, planType);
    _logger.i('PaymentStatusService: Saved pending transaction ref=$reference for user=$userId');
  }

  /// Get the pending transaction reference for a given user, if any.
  Future<Map<String, String>?> getPendingTransactionReference(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final storedUserId = prefs.getString(_pendingTransactionUserIdKey);
    if (storedUserId != userId) return null;

    final reference = prefs.getString(_pendingTransactionRefKey);
    final planType = prefs.getString(_pendingTransactionPlanTypeKey);
    if (reference == null || reference.isEmpty) return null;

    return {
      'reference': reference,
      'planType': planType ?? 'subscription',
    };
  }

  /// Clear the pending transaction reference after successful activation.
  Future<void> clearPendingTransactionReference(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final storedUserId = prefs.getString(_pendingTransactionUserIdKey);
    if (storedUserId == userId) {
      await prefs.remove(_pendingTransactionRefKey);
      await prefs.remove(_pendingTransactionUserIdKey);
      await prefs.remove(_pendingTransactionPlanTypeKey);
      _logger.i('PaymentStatusService: Cleared pending transaction ref for user=$userId');
    }
  }

  /// Check if member has completed payment by looking up in Supabase payments table
  Future<bool> hasCompletedPayment(String memberId) async {
    try {
      final client = SupabaseService.instance.client;
      final response = await client
          .from('payments')
          .select('status')
          .eq('member_id', memberId)
          .eq('status', 'completed')
          .limit(1)
          .maybeSingle();

      return response != null;
    } catch (e) {
      if (kDebugMode) {

        print(
        'PaymentStatusService.hasCompletedPayment: Error checking payment status: $e',
      );

      }
      return false;
    }
  }

  /// Mark payment as completed in Supabase
  Future<void> markPaymentCompleted({
    required String userId,
    required String planName,
    required double amount,
    required String paymentMethod,
    String? transactionId,
  }) async {
    try {
      final client = SupabaseService.instance.client;

      // Validate and normalize plan name
      final validatedPlanName = _validatePlanName(planName);

      await client.from('payments').insert({
        'user_id': userId,
        'plan_name': validatedPlanName,
        'amount': amount.toInt(), // Convert to int for database
        'payment_method': paymentMethod,
        'transaction_id': transactionId,
        'status': 'completed',
        'completed_at': DateTime.now().toIso8601String(),
      });

      // Clear any pending payment data
      await clearPendingPayment(userId);
      if (kDebugMode) {

        print(
        'PaymentStatusService: Payment marked as completed for member $userId',
      );

      }
    } catch (e) {
      if (kDebugMode) {

        print('PaymentStatusService.markPaymentCompleted: Error: $e');

      }
      rethrow;
    }
  }

  /// Validate and normalize plan name to ensure it's one of the valid values
  String _validatePlanName(String planName) {
    const validPlanTypes = ['basic', 'premium', 'annual'];
    if (validPlanTypes.contains(planName.toLowerCase())) {
      return planName.toLowerCase();
    }
    // Default to 'basic' if invalid plan name is provided
    if (kDebugMode) {

      print('Warning: Invalid plan name "$planName", defaulting to "basic"');

    }
    return 'basic';
  }
}
