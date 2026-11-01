import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/deal_approval_popup_service.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../core/utils/display_name_helpers.dart';

class PendingPaymentsPage extends StatefulWidget {
  const PendingPaymentsPage({super.key});

  @override
  State<PendingPaymentsPage> createState() => _PendingPaymentsPageState();
}

class _PendingPaymentsPageState extends State<PendingPaymentsPage> {
  final Logger _logger = Logger();
  final SupabaseClient _supabase = Supabase.instance.client;
  final DealApprovalPopupService _dealService = DealApprovalPopupService();

  Future<List<Map<String, dynamic>>> _fetchPending() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return [];

    final rows = await _supabase
        .from('deal_authorizations')
        .select('''
          id,
          amount,
          status,
          payment_completed_at,
          trusted_partner_discounts(name, businesses(name)),
          businesses!deal_authorizations_business_id_fkey(name),
          created_at
        ''')
        .eq('member_id', user.id)
        .eq('status', 'approved')
        .isFilter('payment_completed_at', null)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _cancelDeal(String dealId) async {
    try {
      // Fetch deal details for notification before cancelling
      final dealData = await _supabase
          .from('deal_authorizations')
          .select('''
            amount,
            member_id,
            trusted_partner_id,
            trusted_partner_discounts(name, trusted_partner_id, businesses(name)),
            profiles(name, surname)
          ''')
          .eq('id', dealId)
          .single();

      final now = DateTime.now().toUtc().toIso8601String();
      await _supabase
          .from('deal_authorizations')
          .update({
            'status': 'rejected',
            'rejection_reason': 'Cancelled by member',
            'updated_at': now,
          })
          .eq('id', dealId);

      // Send push notification to trusted partner
      try {
        final discount = dealData['trusted_partner_discounts'] as Map<String, dynamic>?;
        final member = dealData['profiles'] as Map<String, dynamic>?;
        final trustedPartnerId = dealData['trusted_partner_id'] as String? ??
            discount?['trusted_partner_id'] as String?;
        final memberName = '${member?['name'] ?? 'Member'} ${member?['surname'] ?? ''}'.trim();
        final dealName = discount?['name'] ?? 'Deal';
        final amount = (dealData['amount'] as num?)?.toDouble() ?? 0.0;

        if (trustedPartnerId != null) {
          await NotificationService().notifyTrustedPartnerOfDealCancellation(
            trustedPartnerId: trustedPartnerId,
            dealAuthorizationId: dealId,
            memberName: memberName,
            dealName: dealName,
            amount: amount,
          );

          // Send email to trusted partner (non-blocking)
          try {
            await _supabase.functions.invoke(
              'send-deal-cancellation-email',
              body: {
                'trusted_partner_id': trustedPartnerId,
                'member_name': memberName,
                'deal_name': dealName,
                'amount': amount,
                'deal_authorization_id': dealId,
              },
            );
            _logger.i('Deal cancellation email sent to trusted partner');
          } catch (emailError) {
            _logger.w('Could not send deal cancellation email: $emailError');
          }
        }
      } catch (e) {
        _logger.w('Failed to send cancellation notification: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deal cancelled'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
        setState(() {});
      }
    } catch (e) {
      _logger.e('Cancel deal failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to cancel: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(title: const Text('Pending Payments')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchPending(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(child: Text('No pending payments'));
          }
          return ListView.separated(
            padding: const EdgeInsets.only(
              bottom: 80,
            ), // Add bottom padding to avoid footer
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final row = items[i];
              final discount =
                  row['trusted_partner_discounts'] as Map<String, dynamic>?;
              final business = discount?['businesses'] as Map<String, dynamic>?;
              final directBusiness = row['businesses'] as Map<String, dynamic>?;
              final title = discount?['name'] ?? 'Deal';
              final biz = buildBusinessDisplayName(
                (business?['name'] as String?) ??
                    (directBusiness?['name'] as String?),
              );
              final amount = (row['amount'] ?? 0).toString();
              return ListTile(
                title: Text('$title at $biz'),
                subtitle: Text('Amount: R$amount'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () async {
                        await _dealService.startPaymentForDeal(
                          context,
                          row['id'] as String,
                        );
                        setState(() {});
                      },
                      child: const Text('Authorize'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _cancelDeal(row['id'] as String),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
