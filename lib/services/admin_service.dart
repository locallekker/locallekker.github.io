import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'paystack_service.dart';

class AdminService {
  final supabase = Supabase.instance.client;
  final _logger = Logger();
  
  String get _deleteAuthFunctionUrl {
    final baseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    return '$baseUrl/functions/v1/delete-auth-user';
  }

  Future<void> _deleteAuthUserViaFunction(String userId) async {
    final token = supabase.auth.currentSession?.accessToken;
    if (token == null) {
      _logger.e('No access token available for admin user');
      throw Exception('No authenticated admin token available');
    }

    final resp = await http.post(
      Uri.parse(_deleteAuthFunctionUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'user_id': userId}),
    ).timeout(
      const Duration(seconds: 20),
      onTimeout: () => http.Response('{"error":"Request timed out"}', 504),
    );

    if (resp.statusCode != 200) {
      _logger.e('Auth delete function failed: ${resp.statusCode} ${resp.body}');
      throw Exception(
        'Failed to delete auth user: ${resp.statusCode}',
      );
    }
  }

  /// Retry deleting the auth user only (for when data was already deleted 
  /// but auth deletion failed due to timeout). Safe to call multiple times.
  Future<void> retryDeleteAuthUser(String memberId) async {
    _logger.i('Retrying auth user deletion for: $memberId');
    
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await _deleteAuthUserViaFunction(memberId);
        _logger.i('Auth user deleted successfully on retry attempt $attempt');
        return;
      } catch (e) {
        _logger.w('Auth delete retry attempt $attempt failed: $e');
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: attempt * 3));
        } else {
          throw Exception(
            'Auth account deletion still failing after retries. '
            'Please try again later or delete manually from Supabase dashboard.',
          );
        }
      }
    }
  }

  Future<bool> _cancelPaystackSubscriptionIfExists(String memberId) async {
    try {
      final subscription = await supabase
          .from('subscriptions')
          .select('paystack_subscription_code, status')
          .eq('user_id', memberId)
          .maybeSingle();

      final subscriptionCode =
          subscription?['paystack_subscription_code'] as String?;
      if (subscriptionCode == null || subscriptionCode.isEmpty) {
        _logger.i('No Paystack subscription code for member: $memberId');
        return false;
      }

      // Disable local renewal before the provider call. The scheduled worker
      // must stop immediately even while Paystack cancellation is in flight.
      await supabase
          .from('subscriptions')
          .update({
            'auto_renew': false,
            'renewal_in_progress_at': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', memberId);

      final paystackService = PaystackService();

      String? emailToken;
      try {
        final subscriptionDetails = await paystackService
            .checkSubscriptionStatus(subscriptionCode);
        emailToken = subscriptionDetails?['email_token']?.toString();
      } catch (e) {
        _logger.w(
          'Failed to fetch Paystack subscription details for $subscriptionCode: $e',
        );
      }

      if (emailToken == null || emailToken.isEmpty) {
        _logger.w(
          'Missing email token for Paystack subscription $subscriptionCode; skipping cancellation',
        );
        return false;
      }

      final cancelled = await paystackService.cancelSubscription(
        subscriptionCode,
        emailToken,
      );

      final updateData = <String, dynamic>{
        'auto_renew': false,
        'renewal_in_progress_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (cancelled) {
        updateData['status'] = 'cancelled';
      }

      await supabase
          .from('subscriptions')
          .update(updateData)
          .eq('user_id', memberId);

      _logger.i(
        'Paystack subscription cancel attempt for $memberId (code: $subscriptionCode) result: $cancelled',
      );

      return cancelled;
    } catch (e) {
      _logger.w('Error cancelling Paystack subscription for $memberId: $e');
      return false;
    }
  }

  /// Fetch the admin dashboard via RPC and normalize to a Map.
  /// Falls back to direct table queries when the RPC function is broken or
  /// references columns that no longer exist.
  Future<Map<String, dynamic>> fetchDashboard() async {
    try {
      dynamic res;
      // Prefer a secure SECURITY DEFINER RPC if it's available. Fall back to
      // the older RPC name for backwards compatibility.
      try {
        res = await supabase.rpc('secure_get_admin_dashboard').select();
      } catch (_) {
        try {
          res = await supabase.rpc('get_admin_dashboard').select();
        } catch (_) {
          // RPC unavailable or broken – fall back to direct queries
          res = null;
        }
      }

      // If RPC returns a list (common), take the first element
      if (res is List && res.isNotEmpty) {
        final first = res.first;
        if (first is Map) return Map<String, dynamic>.from(first);
      }

      if (res is Map && res.isNotEmpty) {
        return Map<String, dynamic>.from(res);
      }

      // ── Fallback: build dashboard data from direct table queries ──
      return await _fetchDashboardDirect();
    } catch (e) {
      _logger.e('RPC dashboard failed, trying direct queries: $e');
      try {
        return await _fetchDashboardDirect();
      } catch (e2) {
        throw Exception('Failed to fetch admin dashboard: $e2');
      }
    }
  }

  /// Direct-query fallback when the RPC function is unavailable or broken.
  Future<Map<String, dynamic>> _fetchDashboardDirect() async {
    try {
      // Count active members (exclude deactivated)
      final membersRes = await supabase
          .from('profiles')
          .select('id')
          .eq('role', 'member')
          .neq('is_deactivated', true);
      final totalMembers = (membersRes as List).length;

      // Count active trusted partners from profiles (avoids TP table schema ambiguity)
      final tpRes = await supabase
          .from('profiles')
          .select('id')
          .eq('role', 'trusted_partner')
          .neq('is_deactivated', true);
      final totalTp = (tpRes as List).length;

      // Sum completed subscription payments (online revenue)
      double totalOnline = 0;
      try {
        final paymentsRes = await supabase
            .from('payments')
            .select('amount')
            .eq('status', 'completed');
        for (final p in (paymentsRes as List)) {
          totalOnline += (p['amount'] ?? 0).toDouble();
        }
      } catch (e) {
        _logger.w('Could not fetch payments: $e');
      }

      // Sum approved in-store deal authorizations (in-store revenue)
      double totalInStore = 0;
      List<Map<String, dynamic>> categorySummary = [];
      Map<String, List<Map<String, dynamic>>> categoryDetails = {};
      try {
        final dealsRes = await supabase
            .from('deal_authorizations')
            .select('amount, bill_data, status, trusted_partner_id, businesses!inner(name, category)')
            .eq('status', 'approved');

        for (final d in (dealsRes as List)) {
          // Prefer original_bill_amount from bill_data, fall back to amount
          double dealAmount = 0;
          final billData = d['bill_data'];
          if (billData is Map && billData['original_bill_amount'] != null) {
            dealAmount = (billData['original_bill_amount'] as num).toDouble();
          } else {
            dealAmount = (d['amount'] ?? 0).toDouble();
          }
          totalInStore += dealAmount;

          // Aggregate by business category
          final biz = d['businesses'];
          final category = (biz is Map ? biz['category'] : null)?.toString() ?? 'Uncategorised';
          final bizName = (biz is Map ? biz['name'] : null)?.toString() ?? 'Unknown';

          // Build category summary
          final existing = categorySummary.indexWhere((c) => c['category'] == category);
          if (existing >= 0) {
            categorySummary[existing]['total_amount'] =
                (categorySummary[existing]['total_amount'] as double) + dealAmount;
            categorySummary[existing]['total_count'] =
                (categorySummary[existing]['total_count'] as int) + 1;
          } else {
            categorySummary.add({
              'category': category,
              'total_amount': dealAmount,
              'total_count': 1,
            });
          }

          // Build category details
          categoryDetails.putIfAbsent(category, () => []);
          categoryDetails[category]!.add({
            'product_name': bizName,
            'quantity': 1,
            'amount': dealAmount,
          });
        }
      } catch (e) {
        _logger.w('Could not fetch deal authorizations for in-store revenue: $e');
      }

      return {
        'total_members': totalMembers,
        'total_trusted_partners': totalTp,
        'total_online_purchases': totalOnline,
        'total_in_store_purchases': totalInStore,
        'category_summary': categorySummary,
        'category_details': categoryDetails,
      };
    } catch (e) {
      _logger.e('Direct dashboard query failed: $e');
      // Return safe empty defaults so the UI still renders
      return {
        'total_members': 0,
        'total_trusted_partners': 0,
        'total_online_purchases': 0,
        'total_in_store_purchases': 0,
        'category_summary': <Map<String, dynamic>>[],
        'category_details': <String, dynamic>{},
      };
    }
  }

  /// Permanently delete a member - removes from ALL tables and auth.users
  /// This is a hard delete: profile, subscriptions, QR codes, payments, etc. are all removed
  /// Auth user is deleted via Edge Function so they must re-signup with OTP
  /// Returns deletion details as JSON
  Future<Map<String, dynamic>> deleteMember(String memberId) async {
    try {
      _logger.i('Admin permanently deleting member: $memberId');

      // Step 1: Cancel Paystack subscription to stop future charges
      final cancelled = await _cancelPaystackSubscriptionIfExists(memberId);
      _logger.i(
        'Paystack cancellation attempted for member $memberId (result: $cancelled)',
      );

      // Step 2: Delete all member data from database tables via RPC
      // This hard-deletes from: profiles, subscriptions, user_qr_codes,
      // payments, notifications, memberships, member_receipts, 
      // deal_authorizations, processed_bills, members_card_details,
      // chat_messages, chat_read_receipts, subscription_renewals
      Map<String, dynamic>? rpcResult;
      try {
        final response = await supabase.rpc(
          'admin_delete_member_data',
          params: {'member_user_id': memberId},
        );
        _logger.i('RPC admin_delete_member_data completed: $response');
        if (response is Map) {
          rpcResult = Map<String, dynamic>.from(response);
        }
      } catch (rpcError) {
        _logger.w('RPC admin_delete_member_data failed: $rpcError');
        _logger.i('Falling back to manual table cleanup...');
        
        // Fallback: manually delete from tables if RPC fails
        await _manualDeleteMemberData(memberId);
        rpcResult = {'success': true, 'method': 'manual_fallback'};
      }

      // Safety net: ensure the profile row is truly removed.
      // An older soft-delete version of admin_delete_member_data may still
      // be deployed (it only sets is_deactivated=true), which causes the
      // member to reappear under the "Deactivated" tab after refresh.
      // Force a hard delete here so the row cannot resurface.
      try {
        final remaining = await supabase
            .from('profiles')
            .select('id, is_deactivated')
            .eq('id', memberId)
            .maybeSingle();
        if (remaining != null) {
          _logger.w(
            'Profile row still present after RPC (is_deactivated='
            '${remaining['is_deactivated']}); forcing hard delete.',
          );
          await supabase.from('profiles').delete().eq('id', memberId);
          rpcResult = {
            ...?rpcResult,
            'profile_force_deleted': true,
          };
        }
      } catch (e) {
        _logger.w('Profile hard-delete safety net failed: $e');
      }

      // Step 3: Delete auth user so they can't sign in and must re-signup.
      // The updated SQL RPC (fix_admin_delete_member_hard_delete_auth.sql)
      // already removes the auth.users row directly via SECURITY DEFINER.
      // We treat that as the source of truth and only fall back to the
      // Edge Function if the RPC didn't (or couldn't) delete it.
      final bool authDeletedByRpc = rpcResult?['auth_user_deleted'] == true;
      bool authDeleted = authDeletedByRpc;
      String? authError;

      if (!authDeletedByRpc) {
        _logger.i(
          'RPC did not delete auth user; falling back to delete-auth-user '
          'Edge Function for member: $memberId',
        );

        // Try up to 3 times with delays - Edge Function can be slow to start
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            await _deleteAuthUserViaFunction(memberId);
            _logger.i('Auth user deleted successfully on attempt $attempt');
            authDeleted = true;
            break;
          } catch (e) {
            authError = e.toString();
            _logger.w('Auth delete attempt $attempt failed: $e');
            if (attempt < 3) {
              await Future.delayed(Duration(seconds: attempt * 2));
            }
          }
        }
      } else {
        _logger.i('Auth user deleted by RPC (auth_user_deleted=true)');
      }

      if (!authDeleted) {
        _logger.e(
          'CRITICAL: Auth user NOT deleted. Member will get a recovery '
          'email instead of a fresh signup OTP if they re-register.',
        );
        throw Exception(
          'Member data deleted but auth account removal failed. '
          'The member may get a password reset link instead of fresh signup. '
          'Please try deleting again or contact support. Error: $authError',
        );
      }

      _logger.i('Member permanently deleted: $memberId');

      return {
        'success': true,
        'member_id': memberId,
        'action': 'hard_deleted',
        'auth_deleted': true,
        ...?rpcResult,
      };
    } catch (e) {
      _logger.e('Failed to delete member: $e');
      throw Exception('Failed to delete member: $e');
    }
  }

  /// Fallback manual deletion when RPC function is unavailable or fails
  Future<void> _manualDeleteMemberData(String memberId) async {
    _logger.i('Manual cleanup of member data for: $memberId');
    
    // Delete in order to respect foreign key constraints
    final tablesToDelete = [
      {'table': 'member_receipts', 'column': 'member_id'},
      {'table': 'deal_authorizations', 'column': 'member_id'},
      {'table': 'processed_bills', 'column': 'member_id'},
      {'table': 'chat_messages', 'column': 'sender_id'},
      {'table': 'chat_read_receipts', 'column': 'user_id'},
      {'table': 'members_card_details', 'column': 'user_id'},
      {'table': 'user_qr_codes', 'column': 'user_id'},
      {'table': 'subscription_renewals', 'column': 'user_id'},
      {'table': 'subscriptions', 'column': 'user_id'},
      {'table': 'payments', 'column': 'user_id'},
      {'table': 'notifications', 'column': 'user_id'},
      {'table': 'memberships', 'column': 'user_id'},
    ];

    for (final entry in tablesToDelete) {
      try {
        await supabase
            .from(entry['table']!)
            .delete()
            .eq(entry['column']!, memberId);
        _logger.d('Deleted from ${entry['table']}');
      } catch (e) {
        _logger.w('Failed to delete from ${entry['table']}: $e');
        // Continue with other tables
      }
    }

    // Finally delete profile
    try {
      await supabase.from('profiles').delete().eq('id', memberId);
      _logger.d('Deleted profile');
    } catch (e) {
      _logger.w('Failed to delete profile: $e');
    }
  }

  /// Delete a trusted partner completely
  /// - Archives all receipts to archived_receipts table
  /// - Deletes all deals and associated data
  /// - Deletes business profile
  /// - Deletes from all tables (profiles, memberships, auth.users)
  /// Returns deletion details as JSON
  Future<Map<String, dynamic>> deleteTrustedPartner(
    String tpUserId, {
    String reason = 'Admin deletion',
  }) async {
    try {
      _logger.i('Admin deleting trusted partner: $tpUserId');

      // The SQL function handles everything: archives data, deletes all records
      // including auth.users (SECURITY DEFINER), so no separate auth deletion needed
      final response = await supabase.rpc(
        'admin_delete_trusted_partner',
        params: {'target_user_id': tpUserId, 'deletion_reason': reason},
      );

      _logger.i('Deletion completed: $response');

      if (response is! Map) {
        throw Exception(
          'Unexpected delete response type: ${response.runtimeType}. Response: $response',
        );
      }

      final result = Map<String, dynamic>.from(response);

      if (result['success'] != true) {
        final backendMessage = result['message']?.toString();
        throw Exception(
          backendMessage == null || backendMessage.isEmpty
              ? 'Trusted partner deletion failed: $result'
              : backendMessage,
        );
      }

      // Try edge function as backup for auth deletion (SQL function already attempts it)
      try {
        if (kIsWeb) {
          _logger.i(
            'Skipping delete-auth-user edge call on web (CORS); SQL RPC remains source of truth for deletion.',
          );
        } else {
          final session = supabase.auth.currentSession;
          if (session != null) {
            await supabase.functions.invoke(
              'delete-auth-user',
              body: {'userId': tpUserId},
              headers: {'Authorization': 'Bearer ${session.accessToken}'},
            );
            _logger.i('Auth user cleanup via edge function completed');
          }
        }
      } catch (authError) {
        // Not critical - SQL function already deleted from auth.users
        _logger.w('Edge function auth cleanup skipped: $authError');
      }

      _logger.i('Trusted partner deletion completed: $result');
      return result;
    } catch (e) {
      _logger.e('Failed to delete trusted partner: $e');
      throw Exception('Failed to delete trusted partner: $e');
    }
  }

  /// Check if the current user is an admin
  Future<bool> isAdmin(String userId) async {
    try {
      final response = await supabase.rpc(
        'is_admin',
        params: {'user_id': userId},
      );
      return response == true;
    } catch (e) {
      _logger.e('Failed to check admin status: $e');
      return false;
    }
  }

  /// Deactivate a trusted partner
  /// - Sets is_deactivated flag to true in profiles table
  /// - Marks all deals as inactive
  /// - Removes visibility from members
  Future<Map<String, dynamic>> deactivateTrustedPartner(
    String tpUserId, {
    String reason = 'User requested deactivation',
  }) async {
    try {
      _logger.i('Deactivating trusted partner: $tpUserId with reason: $reason');

      // Update profile to mark as deactivated
      await supabase
          .from('profiles')
          .update({
            'is_deactivated': true,
            'deactivation_reason': reason,
            'deactivated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', tpUserId);

      // Mark all trusted partner discounts as inactive
      await supabase
          .from('trusted_partner_discounts')
          .update({'is_active': false})
          .eq('trusted_partner_id', tpUserId);

      // Mark trusted partner as deactivated in trusted_partners table
      await supabase
          .from('trusted_partners')
          .update({'is_deactivated': true})
          .eq('user_id', tpUserId);

      _logger.i('Trusted partner deactivated successfully');

      return {
        'success': true,
        'tp_user_id': tpUserId,
        'reason': reason,
        'deactivated_at': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      _logger.e('Failed to deactivate trusted partner: $e');
      throw Exception('Failed to deactivate trusted partner: $e');
    }
  }

  /// Deactivate a member
  /// - Sets is_deactivated flag to true in profiles table
  /// - Cancels Paystack subscription
  /// - Deactivates all QR codes
  Future<Map<String, dynamic>> deactivateMember(
    String memberId, {
    String reason = 'User requested deactivation',
  }) async {
    try {
      _logger.i('Deactivating member: $memberId with reason: $reason');

      // Get member's subscription info for Paystack cancellation
      final subscriptionData = await supabase
          .from('subscriptions')
          .select('paystack_subscription_code, status')
          .eq('user_id', memberId)
          .maybeSingle();

      // Attempt to cancel Paystack subscription to stop future charges
      final cancelled = await _cancelPaystackSubscriptionIfExists(memberId);
      _logger.i(
        'Paystack cancellation attempted for member $memberId during deactivation (result: $cancelled)',
      );

      // Update profile to mark as deactivated
      await supabase
          .from('profiles')
          .update({
            'is_deactivated': true,
            'deactivation_reason': reason,
            'deactivated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', memberId);

      // Update subscription status to deactivated
      if (subscriptionData != null) {
        await supabase
            .from('subscriptions')
            .update({
              // Use valid status per constraint
              'status': 'inactive',
              'auto_renew': false,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', memberId);
      }

      // Delete all QR codes for the member (avoids unique constraint violation)
      await supabase.from('user_qr_codes').delete().eq('user_id', memberId);

      _logger.i('Member deactivated successfully');

      return {
        'success': true,
        'member_id': memberId,
        'reason': reason,
        'deactivated_at': DateTime.now().toIso8601String(),
        'paystack_subscription_code':
            subscriptionData?['paystack_subscription_code'],
      };
    } catch (e) {
      _logger.e('Failed to deactivate member: $e');
      throw Exception('Failed to deactivate member: $e');
    }
  }

  /// Fetch deactivated trusted partners
  Future<List<Map<String, dynamic>>> getDeactivatedTrustedPartners() async {
    try {
      final response = await supabase
          .from('profiles')
          .select('*')
          .eq('role', 'trusted_partner')
          .eq('is_deactivated', true)
          .order('deactivated_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.e('Failed to fetch deactivated trusted partners: $e');
      throw Exception('Failed to fetch deactivated trusted partners: $e');
    }
  }

  /// Fetch deactivated members
  Future<List<Map<String, dynamic>>> getDeactivatedMembers() async {
    try {
      final response = await supabase
          .from('profiles')
          .select('*')
          .eq('role', 'member')
          .eq('is_deactivated', true)
          .order('deactivated_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.e('Failed to fetch deactivated members: $e');
      throw Exception('Failed to fetch deactivated members: $e');
    }
  }

  /// Reactivate a deactivated trusted partner
  Future<Map<String, dynamic>> reactivateTrustedPartner(String tpUserId) async {
    try {
      _logger.i('Reactivating trusted partner: $tpUserId');

      await supabase
          .from('profiles')
          .update({
            'is_deactivated': false,
            'deactivation_reason': null,
            'deactivated_at': null,
          })
          .eq('id', tpUserId);

      await supabase
          .from('trusted_partners')
          .update({'is_deactivated': false})
          .eq('user_id', tpUserId);

      _logger.i('Trusted partner reactivated successfully');

      return {'success': true, 'tp_user_id': tpUserId};
    } catch (e) {
      _logger.e('Failed to reactivate trusted partner: $e');
      throw Exception('Failed to reactivate trusted partner: $e');
    }
  }

  /// Reactivate a deactivated member
  Future<Map<String, dynamic>> reactivateMember(String memberId) async {
    try {
      _logger.i('Reactivating member: $memberId');

      await supabase
          .from('profiles')
          .update({
            'is_deactivated': false,
            'deactivation_reason': null,
            'deactivated_at': null,
          })
          .eq('id', memberId);

      _logger.i('Member reactivated successfully');

      return {'success': true, 'member_id': memberId};
    } catch (e) {
      _logger.e('Failed to reactivate member: $e');
      throw Exception('Failed to reactivate member: $e');
    }
  }
}
