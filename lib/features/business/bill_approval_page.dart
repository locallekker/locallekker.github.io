import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/bill_approval_service.dart';
import '../../services/paystack_service.dart';
import '../../services/supabase_service.dart';
import 'package:flutter/foundation.dart';

class BillApprovalPage extends StatefulWidget {
  const BillApprovalPage({super.key});

  @override
  State<BillApprovalPage> createState() => _BillApprovalPageState();
}

class _BillApprovalPageState extends State<BillApprovalPage> {
  final BillApprovalService _approvalService = BillApprovalService();
  final PaystackService _paystackService = PaystackService();

  List<Map<String, dynamic>> _pendingApprovals = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPendingApprovals();
  }

  Future<void> _loadPendingApprovals() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = SupabaseService.instance.getCurrentUser();
      if (currentUser == null) {
        throw Exception('No authenticated user');
      }

      _pendingApprovals = await _approvalService.getPendingApprovals(
        currentUser.id,
      );
      if (kDebugMode) {

        print('Found ${_pendingApprovals.length} pending approvals');

      }
    } catch (e) {
      if (kDebugMode) {

        print('Error loading approvals: $e');

      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load approvals: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _approveBill(String approvalId, String billId) async {
    try {
      await _approvalService.approveBill(approvalId: approvalId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bill approved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      _loadPendingApprovals(); // Refresh list
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to approve bill: $e')));
      }
    }
  }

  Future<void> _rejectBill(String approvalId, String billId) async {
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Bill'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please provide a reason for rejection:'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: 'Reason for rejection',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (result == true && reasonController.text.isNotEmpty) {
      try {
        await _approvalService.rejectBill(
          approvalId: approvalId,
          rejectionReason: reasonController.text,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bill rejected'),
              backgroundColor: Colors.red,
            ),
          );
        }

        _loadPendingApprovals(); // Refresh list
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to reject bill: $e')));
        }
      }
    }
  }

  Future<void> _processPayment(
    String billId,
    double amount,
    String memberEmail,
  ) async {
    try {
      // Fetch the trusted partner's Paystack subaccount so funds settle to the partner
      final currentUser = SupabaseService.instance.getCurrentUser();
      if (currentUser == null) {
        throw Exception('No authenticated user');
      }

      String? subaccountCode;
      try {
        final bankingData = await SupabaseService.instance.client
            .from('trusted_partner_bank_accounts')
            .select('subaccount_code, subaccount_active')
            .eq('user_id', currentUser.id)
            .eq('is_active', true)
            .maybeSingle();

        if (bankingData != null &&
            bankingData['subaccount_code'] != null &&
            (bankingData['subaccount_active'] ?? false)) {
          subaccountCode = bankingData['subaccount_code'] as String?;
        }
      } catch (e) {
        // If this fails, we'll handle as no subaccount below
      }

      if (subaccountCode == null || subaccountCode.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No active Paystack subaccount found. Please set up banking details to receive payments.',
              ),
            ),
          );
        }
        return; // Do not allow payment to route to platform account
      }

      // Create Paystack payment routed to trusted partner subaccount
      await _paystackService.startOneTimePayment(
        itemName: 'Bill Payment',
        itemDescription: 'Payment for approved bill',
        amount: amount,
        userId: memberEmail, // Use email as identifier for Paystack
        userEmail: memberEmail,
        subaccountCode: subaccountCode,
      );

      // Mark bill as paid in-app
      await _approvalService.markBillAsPaidInApp(
        billId: billId,
        paymentId: 'payment_pending', // Will be updated when Paystack completes
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment initiated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Payment failed: $e')));
      }
    }
  }

  Future<void> _markAsPaidPhysically(String billId) async {
    try {
      await _approvalService.markBillAsPaidPhysically(billId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bill marked as paid physically'),
            backgroundColor: Colors.blue,
          ),
        );
      }

      _loadPendingApprovals(); // Refresh list
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to mark as paid: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Bill Approvals'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingApprovals,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pendingApprovals.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Text('No pending approvals', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 8),
                  Text(
                    'All bills have been reviewed',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _pendingApprovals.length,
              itemBuilder: (context, index) {
                final approval = _pendingApprovals[index];
                final bill =
                    approval['processed_bills'] as Map<String, dynamic>?;
                final member = bill?['member'] as Map<String, dynamic>?;

                if (bill == null) return const SizedBox.shrink();

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Member info
                        Row(
                          children: [
                            const Icon(Icons.person, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              '${member?['name'] ?? 'Unknown'} ${member?['surname'] ?? ''}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Bill details
                        Text(
                          'Original: R${bill['original_total']?.toStringAsFixed(2) ?? '0.00'}',
                          style: const TextStyle(color: Colors.red),
                        ),
                        Text(
                          'Discount: R${bill['discount_amount']?.toStringAsFixed(2) ?? '0.00'}',
                          style: const TextStyle(color: Colors.green),
                        ),
                        Text(
                          'Total: R${bill['discounted_total']?.toStringAsFixed(2) ?? '0.00'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Action buttons
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _approveBill(approval['id'], bill['id']),
                                icon: const Icon(Icons.check),
                                label: const Text('Approve'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _rejectBill(approval['id'], bill['id']),
                                icon: const Icon(Icons.close),
                                label: const Text('Reject'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Payment options (shown after approval)
                        if (approval['status'] == 'approved') ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const Text(
                            'Payment Method:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _processPayment(
                                    bill['id'],
                                    bill['discounted_total'] ?? 0.0,
                                    member?['email'] ?? '',
                                  ),
                                  icon: const Icon(Icons.payment),
                                  label: const Text('In-App Payment'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _markAsPaidPhysically(bill['id']),
                                  icon: const Icon(Icons.handshake),
                                  label: const Text('Physical Payment'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
