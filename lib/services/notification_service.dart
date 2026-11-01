import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../models/notification.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final Logger _logger = Logger();

  Future<List<NotificationModel>> getUserNotifications(
    String userId, {
    bool unreadOnly = false,
  }) async {
    try {
      var query = _supabase
          .from('notifications')
          .select()
          .eq('user_id', userId);

      if (unreadOnly) {
        query = query.eq('is_read', false);
      }

      final response = await query.order('created_at', ascending: false);
      return response.map((json) => NotificationModel.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load notifications: $e');
    }
  }

  Future<int> getUnreadNotificationCount(String userId) async {
    try {
      final response = await _supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);

      return response.length;
    } catch (e) {
      throw Exception('Failed to get unread notification count: $e');
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

  Future<void> markAllNotificationsAsRead(String userId) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
    } catch (e) {
      throw Exception('Failed to mark all notifications as read: $e');
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    try {
      await _supabase.from('notifications').delete().eq('id', notificationId);
    } catch (e) {
      throw Exception('Failed to delete notification: $e');
    }
  }

  // Real-time subscription for notifications
  Stream<List<NotificationModel>> subscribeToNotifications(String userId) {
    return _supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map(
          (data) =>
              data.map((json) => NotificationModel.fromJson(json)).toList(),
        );
  }

  // Create notification using RPC bypass to avoid RLS issues
  // (e.g. member creating a notification for a trusted partner)
  Future<NotificationModel> createNotification({
    required String userId,
    required String title,
    required String message,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    try {
      // Use SECURITY DEFINER RPC function to bypass RLS
      // This ensures cross-user notifications (member → TP) always succeed
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

      final notificationData = (result as List).first as Map<String, dynamic>;
      if (kDebugMode) {
        _logger.d('Notification created via RPC bypass for user $userId, type: $type');
      }
      return NotificationModel.fromJson(notificationData);
    } catch (e) {
      _logger.e('Failed to create notification via RPC: $e');
      // Fallback to direct insert.
      // NOTE: We intentionally do NOT chain .select().single() here because
      // cross-user notifications (e.g. TP creating notification for member)
      // will fail the SELECT RLS check (user_id != auth.uid()). The INSERT
      // itself succeeds, which is all we need — the database webhook will
      // trigger the push notification edge function.
      try {
        await _supabase
            .from('notifications')
            .insert({
              'user_id': userId,
              'title': title,
              'message': message,
              'type': type,
              'data': data,
              'is_read': false,
            });
        _logger.i('Notification created via direct insert fallback for user $userId, type: $type');
        return NotificationModel(
          id: '',
          userId: userId,
          title: title,
          message: message,
          type: type,
          data: data,
          isRead: false,
          createdAt: DateTime.now(),
        );
      } catch (fallbackError) {
        _logger.e('Direct insert fallback also failed: $fallbackError');
        throw Exception('Failed to create notification: $e');
      }
    }
  }

  /// Check if user has any unread payment failure notifications
  Future<bool> hasPaymentFailureNotification(String userId) async {
    try {
      final response = await _supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('type', 'payment_failure')
          .eq('is_read', false)
          .limit(1);

      return response.isNotEmpty;
    } catch (e) {
      throw Exception('Failed to check payment failure notification: $e');
    }
  }

  /// Get payment-related notifications (failures, renewals, etc.)
  Future<List<NotificationModel>> getPaymentNotifications(String userId) async {
    try {
      final response = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .inFilter('type', [
            'payment_failure',
            'subscription_renewal',
            'payment',
          ])
          .order('created_at', ascending: false)
          .limit(20);

      return response.map((json) => NotificationModel.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load payment notifications: $e');
    }
  }

  /// Get the most recent payment failure notification
  Future<NotificationModel?> getLatestPaymentFailure(String userId) async {
    try {
      final response = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .eq('type', 'payment_failure')
          .order('created_at', ascending: false)
          .limit(1);

      if (response.isEmpty) return null;
      return NotificationModel.fromJson(response.first);
    } catch (e) {
      throw Exception('Failed to get latest payment failure: $e');
    }
  }

  /// Notify all admins with a message
  /// Used for system-level events that require admin attention
  Future<void> notifyAdmins({
    required String title,
    required String message,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    try {
      // Get all admin users
      final adminUsers = await _supabase
          .from('profiles')
          .select('id')
          .eq('role', 'admin');

      if (adminUsers.isEmpty) {
        throw Exception('No admin users found to notify');
      }

      // Create notification for each admin
      final notifications = (adminUsers as List).map((admin) {
        return {
          'user_id': admin['id'],
          'title': title,
          'message': message,
          'type': type,
          'data': data,
          'is_read': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        };
      }).toList();

      // Insert all notifications
      await _supabase.from('notifications').insert(notifications);
    } catch (e) {
      throw Exception('Failed to notify admins: $e');
    }
  }

  /// Notify admins when a TP uploads banking details
  Future<void> notifyAdminsOfBankingDetailsUpdate({
    required String trustedPartnerId,
    required String trustedPartnerName,
    required String businessName,
    required String subaccountCode,
    required String bankName,
  }) async {
    await notifyAdmins(
      title: '🏦 Banking Details Added',
      message:
          '$businessName has added/updated banking details. Verify Paystack subaccount: $subaccountCode',
      type: 'banking_details_added',
      data: {
        'trusted_partner_id': trustedPartnerId,
        'trusted_partner_name': trustedPartnerName,
        'business_name': businessName,
        'subaccount_code': subaccountCode,
        'bank_name': bankName,
      },
    );
  }

  /// Notify admins when a Paystack subaccount needs approval
  Future<void> notifyAdminsOfSubaccountApproval({
    required String trustedPartnerId,
    required String trustedPartnerName,
    required String businessName,
    required String subaccountCode,
    required String bankName,
    required String accountNumber,
  }) async {
    await notifyAdmins(
      title: '✅ Subaccount Approval Required',
      message:
          'Please approve Paystack subaccount for $businessName on Paystack dashboard',
      type: 'subaccount_approval_required',
      data: {
        'trusted_partner_id': trustedPartnerId,
        'trusted_partner_name': trustedPartnerName,
        'business_name': businessName,
        'subaccount_code': subaccountCode,
        'bank_name': bankName,
        'account_number': accountNumber,
      },
    );
  }

  /// Notify trusted partner when they receive a deal request from a member
  Future<void> notifyTrustedPartnerOfDealRequest({
    required String trustedPartnerId,
    required String dealAuthorizationId,
    required String memberId,
    required String memberName,
    required String dealName,
    required double amount,
    required String paymentMethod,
    int? quantity,
  }) async {
    try {
      final quantityText = quantity != null && quantity > 1
          ? ' (x$quantity)'
          : '';
      final paymentMethodText = paymentMethod == 'pos' ? 'In-Store' : 'In-App';

      await createNotification(
        userId: trustedPartnerId,
        title: '🛒 New Deal Request',
        message:
            '$memberName requested: $dealName$quantityText - R${amount.toStringAsFixed(2)} ($paymentMethodText)',
        type: 'deal_request',
        data: {
          'deal_authorization_id': dealAuthorizationId,
          'member_id': memberId,
          'member_name': memberName,
          'deal_name': dealName,
          'amount': amount,
          'payment_method': paymentMethod,
          'quantity': quantity,
        },
      );
    } catch (e) {
      throw Exception('Failed to notify trusted partner of deal request: $e');
    }
  }

  /// Notify member when trusted partner approves their deal request
  Future<void> notifyMemberOfDealApproval({
    required String memberId,
    required String dealAuthorizationId,
    required String trustedPartnerName,
    required String businessName,
    required String dealName,
    required double amount,
    required String paymentMethod,
    int? quantity,
  }) async {
    try {
      final bool isPOSPayment = paymentMethod == 'pos';
      final quantityText = quantity != null && quantity > 1
          ? ' (x$quantity)'
          : '';

      final String title = isPOSPayment
          ? '✅ Deal Approved - Visit Store'
          : '✅ Deal Approved - Pay Now';

      final String message = isPOSPayment
          ? '$businessName approved your request for $dealName$quantityText. Visit the store to complete payment (R${amount.toStringAsFixed(2)}).'
          : '$businessName approved your request for $dealName$quantityText. Tap to pay R${amount.toStringAsFixed(2)} now.';

      await createNotification(
        userId: memberId,
        title: title,
        message: message,
        type: isPOSPayment ? 'pos_deal_approved' : 'deal_approved',
        data: {
          'deal_authorization_id': dealAuthorizationId,
          'trusted_partner_name': trustedPartnerName,
          'business_name': businessName,
          'deal_name': dealName,
          'amount': amount,
          'payment_method': paymentMethod,
          'quantity': quantity,
        },
      );
    } catch (e) {
      throw Exception('Failed to notify member of deal approval: $e');
    }
  }

  /// Notify member when trusted partner rejects their deal request
  Future<void> notifyMemberOfDealRejection({
    required String memberId,
    required String dealAuthorizationId,
    required String trustedPartnerName,
    required String businessName,
    required String dealName,
    required String rejectionReason,
  }) async {
    try {
      await createNotification(
        userId: memberId,
        title: '❌ Deal Request Declined',
        message:
            '$businessName declined your request for $dealName. Reason: $rejectionReason',
        type: 'deal_rejected',
        data: {
          'deal_authorization_id': dealAuthorizationId,
          'trusted_partner_name': trustedPartnerName,
          'business_name': businessName,
          'deal_name': dealName,
          'rejection_reason': rejectionReason,
        },
      );
    } catch (e) {
      throw Exception('Failed to notify member of deal rejection: $e');
    }
  }

  /// Notify trusted partner when member completes payment
  Future<void> notifyTrustedPartnerOfPayment({
    required String trustedPartnerId,
    required String dealAuthorizationId,
    required String memberId,
    required String memberName,
    required String dealName,
    required double amount,
    required String receiptNumber,
    required String businessName,
  }) async {
    try {
      await createNotification(
        userId: trustedPartnerId,
        title: '💰 Payment Received',
        message:
            '$memberName paid R${amount.toStringAsFixed(2)} for $dealName. Receipt #$receiptNumber generated.',
        type: 'payment_received',
        data: {
          'deal_authorization_id': dealAuthorizationId,
          'member_id': memberId,
          'member_name': memberName,
          'deal_name': dealName,
          'amount': amount,
          'receipt_number': receiptNumber,
          'business_name': businessName,
        },
      );
    } catch (e) {
      throw Exception('Failed to notify trusted partner of payment: $e');
    }
  }

  /// Notify member of successful payment and receipt generation
  Future<void> notifyMemberOfPaymentSuccess({
    required String memberId,
    required String dealAuthorizationId,
    required String businessName,
    required String dealName,
    required double amount,
    required String receiptNumber,
  }) async {
    try {
      await createNotification(
        userId: memberId,
        title: '✅ Payment Successful',
        message:
            'Your payment of R${amount.toStringAsFixed(2)} to $businessName for $dealName was successful. Receipt #$receiptNumber has been generated.',
        type: 'payment_success',
        data: {
          'deal_authorization_id': dealAuthorizationId,
          'business_name': businessName,
          'deal_name': dealName,
          'amount': amount,
          'receipt_number': receiptNumber,
        },
      );
    } catch (e) {
      throw Exception('Failed to notify member of payment success: $e');
    }
  }

  /// Notify trusted partner when member cancels an approved deal
  Future<void> notifyTrustedPartnerOfDealCancellation({
    required String trustedPartnerId,
    required String dealAuthorizationId,
    required String memberName,
    required String dealName,
    required double amount,
  }) async {
    try {
      await createNotification(
        userId: trustedPartnerId,
        title: '❌ Deal Cancelled by Member',
        message:
            '$memberName cancelled their deal for $dealName (R${amount.toStringAsFixed(2)}).',
        type: 'deal_cancelled',
        data: {
          'deal_authorization_id': dealAuthorizationId,
          'member_name': memberName,
          'deal_name': dealName,
          'amount': amount,
        },
      );
    } catch (e) {
      throw Exception('Failed to notify trusted partner of deal cancellation: $e');
    }
  }

  /// Notify admins when a trusted partner completes signup and is verified/approved
  Future<void> notifyAdminsOfPartnerApproval({
    required String partnerId,
    required String partnerName,
    required String businessName,
    required String partnerEmail,
  }) async {
    try {
      await notifyAdmins(
        title: '🎉 New Partner Approved',
        message:
            '$partnerName ($businessName) has been verified and moved to the approved partners tab.',
        type: 'partner_approved',
        data: {
          'partner_id': partnerId,
          'partner_name': partnerName,
          'business_name': businessName,
          'partner_email': partnerEmail,
        },
      );
    } catch (e) {
      throw Exception('Failed to notify admins of partner approval: $e');
    }
  }
}
