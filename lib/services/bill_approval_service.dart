import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class BillApproval {
  final String id;
  final String billId;
  final String partnerId;
  final String status;
  final String? reviewNotes;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  BillApproval({
    required this.id,
    required this.billId,
    required this.partnerId,
    required this.status,
    this.reviewNotes,
    this.reviewedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BillApproval.fromMap(Map<String, dynamic> map) {
    return BillApproval(
      id: map['id'],
      billId: map['bill_id'],
      partnerId: map['partner_id'],
      status: map['status'],
      reviewNotes: map['review_notes'],
      reviewedAt: map['reviewed_at'] != null
          ? DateTime.parse(map['reviewed_at'])
          : null,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }
}

class BillApprovalService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get processed (approved/rejected) approvals for a partner
  Future<List<Map<String, dynamic>>> getPendingApprovals(
    String partnerId,
  ) async {
    try {
      // First get the business ID for this partner
      final businessResponse = await _supabase
          .from('businesses')
          .select('id')
          .eq('owner_member_id', partnerId)
          .maybeSingle();

      if (businessResponse == null) {
        if (kDebugMode) {

          print('No business found for partner: $partnerId');

        }
        return [];
      }

      final businessId = businessResponse['id'];

      // Query deal_authorizations for pending requests
      final response = await _supabase
          .from('deal_authorizations')
          .select('''
            *,
            member:profiles!deal_authorizations_member_id_fkey (
              id,
              name,
              surname,
              email,
              profile_photo_url
            ),
            discount:trusted_partner_discounts (
              id,
              description,
              percentage
            )
          ''')
          .eq('business_id', businessId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      if (kDebugMode) {


        print('Found ${(response as List).length} processed approvals');


      }
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) {

        print('Error fetching processed approvals: $e');

      }
      return [];
    }
  }

  /// Approve a bill (updates deal_authorization)
  Future<void> approveBill({
    required String approvalId,
    String? reviewNotes,
  }) async {
    try {
      await _supabase
          .from('deal_authorizations')
          .update({
            'status': 'approved',
            'notes': reviewNotes,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', approvalId);
    } catch (e) {
      throw Exception('Failed to approve bill: $e');
    }
  }

  /// Reject a bill (updates deal_authorization)
  Future<void> rejectBill({
    required String approvalId,
    required String rejectionReason,
    String? reviewNotes,
  }) async {
    try {
      await _supabase
          .from('deal_authorizations')
          .update({
            'status': 'rejected',
            'notes': reviewNotes ?? rejectionReason,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', approvalId);
    } catch (e) {
      throw Exception('Failed to reject bill: $e');
    }
  }

  /// Mark bill as paid in-app
  Future<void> markBillAsPaidInApp({
    required String billId,
    required String paymentId,
  }) async {
    try {
      await _supabase
          .from('processed_bills')
          .update({'payment_method': 'in_app', 'payment_id': paymentId})
          .eq('id', billId);
    } catch (e) {
      throw Exception('Failed to mark bill as paid: $e');
    }
  }

  /// Mark bill as paid physically
  Future<void> markBillAsPaidPhysically(String billId) async {
    try {
      await _supabase
          .from('processed_bills')
          .update({'payment_method': 'physical'})
          .eq('id', billId);
    } catch (e) {
      throw Exception('Failed to mark bill as paid physically: $e');
    }
  }

  /// Get approval statistics for a partner
  Future<Map<String, dynamic>> getApprovalStats(String partnerId) async {
    try {
      final response = await _supabase
          .from('bill_approvals')
          .select('status')
          .eq('partner_id', partnerId);

      final stats = {'pending': 0, 'approved': 0, 'rejected': 0};
      for (final approval in response as List) {
        final status = approval['status'] as String;
        if (stats.containsKey(status)) {
          stats[status] = (stats[status] as int) + 1;
        }
      }

      return stats;
    } catch (e) {
      return {'pending': 0, 'approved': 0, 'rejected': 0};
    }
  }
}
