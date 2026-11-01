import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import '../../models/deal_authorization.dart';
import '../../services/discount_service.dart';
import '../../services/deal_authorization_service.dart';
import '../../services/supabase_service.dart';
import '../../core/utils/display_name_helpers.dart';
import 'receipt_generator_page.dart';
import 'package:flutter/foundation.dart';

/// Local Lekker brand palette.
const Color kBrandBlue = Color(0xFF0E5BA0);
const Color kBrandGreen = Color(0xFF3C8C44);
const Color kBrandYellow = Color(0xFFF4B400);

class DealAuthorizationDashboard extends StatefulWidget {
  const DealAuthorizationDashboard({super.key});

  @override
  State<DealAuthorizationDashboard> createState() =>
      _DealAuthorizationDashboardState();
}

class _DealAuthorizationDashboardState
    extends State<DealAuthorizationDashboard> {
  final DiscountService _discountService = DiscountService();
  final DealAuthorizationService _dealService = DealAuthorizationService();
  final Logger _logger = Logger();

  List<DealAuthorization> _pendingAuthorizations = [];
  List<DealAuthorization> _approvedAuthorizations = [];
  List<Map<String, dynamic>> _receipts = [];
  bool _isLoading = true;
  // _isRefreshing is true during background reloads triggered by realtime
  // events. We keep the existing list visible instead of showing a blank
  // loading spinner, preventing the "second deal disappears" visual glitch.
  bool _isRefreshing = false;
  RealtimeChannel? _dealAuthChannel;

  @override
  void initState() {
    super.initState();
    _loadAuthorizations();
    _setupRealtimeDealAuthSubscription();
  }

  @override
  void dispose() {
    _dealAuthChannel?.unsubscribe();
    super.dispose();
  }

  /// Subscribe to realtime changes on deal_authorizations for auto-refresh
  Future<void> _setupRealtimeDealAuthSubscription() async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) return;

      final businessResponse = await SupabaseService.instance.client
          .from('businesses')
          .select('id')
          .eq('owner_member_id', user.id)
          .maybeSingle();

      if (businessResponse == null) return;

      final businessId = businessResponse['id'] as String;

      _dealAuthChannel = SupabaseService.instance.client
          .channel('dashboard_deal_auth_${user.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'deal_authorizations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'business_id',
              value: businessId,
            ),
            callback: (payload) {
              if (kDebugMode) {
                print('[DASHBOARD_REALTIME] Deal auth change detected, refreshing...');
              }
              _loadAuthorizations(background: true);
            },
          )
          .subscribe();

      _logger.i('Dashboard realtime subscription active for business $businessId');
    } catch (e) {
      _logger.e('Failed to set up dashboard realtime subscription: $e');
    }
  }

  Future<void> _loadAuthorizations({bool background = false}) async {
    if (background) {
      // For realtime-triggered refreshes keep the current list visible;
      // only show the top-level spinner on the very first load.
      setState(() => _isRefreshing = true);
    } else {
      setState(() => _isLoading = true);
    }
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user != null) {
        final allAuthorizations = await _discountService
            .getTrustedPartnerDealAuthorizations(user.id);

        if (kDebugMode) {
          print(
            '📊 Dashboard: Loaded ${allAuthorizations.length} total authorizations',
          );
        }

        // Debug: Log payment_completed_at status for all deals
        for (var auth in allAuthorizations) {
          if (kDebugMode) {
            print(
              '📊 Deal ${auth.id.substring(0, 8)}: status=${auth.status}, paymentCompletedAt=${auth.paymentCompletedAt}',
            );
          }
        }

        setState(() {
          _pendingAuthorizations = allAuthorizations
              .where((auth) => auth.status == 'pending')
              .toList();
          // Approved: Show ALL approved, rejected, and completed deals
          // This includes:
          // - approved (waiting for payment)
          // - rejected (cancelled by TP or member)
          // - completed (payment done, receipt generated)
          // Deals stay in Approved tab forever for record keeping
          _approvedAuthorizations = allAuthorizations
              .where(
                (auth) =>
                    auth.status == 'approved' ||
                    auth.status == 'rejected' ||
                    auth.status == 'completed',
              )
              .toList();

          if (kDebugMode) {
            print(
              '📊 Dashboard counts: Pending=${_pendingAuthorizations.length}, Approved=${_approvedAuthorizations.length}',
            );
          }
        });

        // Load receipts for Receipts tab. Mirror the background flag so
        // realtime-triggered refreshes never surface transient network
        // hiccups as scary error banners.
        await _loadReceipts(silent: background);

        // Create notifications for any existing pending authorizations
        // This ensures trusted partners get notified of pending requests
        await _discountService
            .createNotificationsForExistingPendingAuthorizations(user.id);

        // Check for approved POS deals that need payment confirmation
        if (mounted) {
          _checkForPendingPOSPayments();
        }
      }
    } catch (e) {
      // Background refreshes (realtime-triggered) must stay silent: a momentary
      // connection abort right after approving a deal should not alarm the
      // partner when the data will reload on the next event or manual refresh.
      if (mounted && !background) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isTransientNetworkError(e)
                  ? 'No internet connection. Check your network and try again.'
                  : 'Failed to load authorizations: $e',
            ),
          ),
        );
      } else {
        _logger.w('Authorization refresh failed (background=$background): $e');
      }
    } finally {
      if (background) {
        if (mounted) setState(() => _isRefreshing = false);
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Returns true for recoverable network blips (e.g. "Software caused
  /// connection abort") that commonly fire during the burst of activity right
  /// after a deal is approved. These should never be surfaced as error banners.
  bool _isTransientNetworkError(Object e) {
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('ClientException') ||
        s.contains('Failed host lookup') ||
        s.contains('connection abort') ||
        s.contains('Connection closed') ||
        s.contains('Connection reset') ||
        s.contains('connection error') ||
        s.contains('TimeoutException');
  }

  Future<void> _loadReceipts({bool silent = false}) async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return;

    if (kDebugMode) {
      print('🧾 Loading receipts for trusted partner: ${user.id}');
    }

    const maxAttempts = 2;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await SupabaseService.instance.client
            .from('deal_receipts')
            .select()
            .eq('trusted_partner_id', user.id)
            .order('created_at', ascending: false);

        if (kDebugMode) {
          print('🧾 Loaded ${response.length} receipts');
        }

        if (!mounted) return;
        setState(() {
          _receipts = List<Map<String, dynamic>>.from(response);
        });
        return;
      } catch (e) {
        lastError = e;
        // Retry once for transient network blips before giving up.
        if (_isTransientNetworkError(e) && attempt < maxAttempts) {
          _logger.w('Transient receipt fetch failure (attempt $attempt): $e');
          await Future.delayed(const Duration(milliseconds: 600));
          continue;
        }
        break;
      }
    }

    _logger.e('Error loading receipts: $lastError');

    // Never show a banner for silent (background/realtime) refreshes or for
    // transient connection hiccups — the list reloads on the next refresh.
    if (!mounted || silent || _isTransientNetworkError(lastError!)) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to load receipts: $lastError')),
    );
  }

  void _checkForPendingPOSPayments() {
    // Find the first approved POS deal that hasn't been paid yet
    DealAuthorization? pendingPOSDeal;

    try {
      pendingPOSDeal = _approvedAuthorizations.firstWhere(
        (auth) =>
            auth.status == 'approved' &&
            auth.paymentMethod == 'pos' &&
            auth.paymentCompletedAt == null &&
            auth.completedAt == null,
      );
    } catch (e) {
      // No pending POS deal found
      return;
    }

    // If found, show the confirmation dialog after a short delay
    if (mounted) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && pendingPOSDeal != null) {
          if (kDebugMode) {
            print(
              '🔔 Auto-showing POS payment confirmation for deal: ${pendingPOSDeal.id}',
            );
          }
          _showPOSPaymentConfirmation(pendingPOSDeal);
        }
      });
    }
  }

  Future<void> _approveAuthorization(String dealId) async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) return;

      // Get deal details to check payment method
      final dealData = await SupabaseService.instance.client
          .from('deal_authorizations')
          .select('''
            *,
            trusted_partner_discounts (
              id,
              name,
              description
            ),
            profiles!deal_authorizations_member_id_fkey (
              id,
              name,
              surname
            )
          ''')
          .eq('id', dealId)
          .single();

      final paymentMethod = dealData['payment_method'] as String?;

      // Approve the deal first
      await _dealService.approveDealAuthorization(
        dealId: dealId,
        trustedPartnerId: user.id,
      );

      if (!mounted) return;

      // If POS payment, defer dialog showing to next frame to avoid context lifecycle issues
      if (paymentMethod == 'pos') {
        // Reload to get the updated auth object
        try {
          final updatedDealData = await SupabaseService.instance.client
              .from('deal_authorizations')
              .select('''
                *,
                trusted_partner_discounts (
                  id,
                  name,
                  description,
                  item_name,
                  item_price,
                  percentage,
                  fixed_amount,
                  is_active
                ),
                profiles!deal_authorizations_member_id_fkey (
                  id,
                  name,
                  surname,
                  email
                )
              ''')
              .eq('id', dealId)
              .single();

          final auth = DealAuthorization.fromJson(updatedDealData);

          if (mounted) {
            // Defer dialog to next frame to ensure widget tree is stable during chained approvals
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showPOSPaymentConfirmation(auth);
              }
            });
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error loading payment details: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          _loadAuthorizations();
        }
      } else {
        // For in-app payment, just show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Authorization approved! Member will complete payment in the app.',
            ),
            backgroundColor: kBrandGreen,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
          ),
        );
        _loadAuthorizations(); // Refresh the list
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().contains('502') ||
                e.toString().contains('Bad Gateway')
            ? 'Server temporarily unavailable. Please try again in a moment.'
            : 'Failed to approve authorization. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          ),
        );
      }
    }
  }

  Future<void> _rejectAuthorization(String dealId, String reason) async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) return;

      await _dealService.rejectDealAuthorization(
        dealId: dealId,
        trustedPartnerId: user.id,
        rejectionReason: reason,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authorization rejected'),
            backgroundColor: kBrandYellow,
          ),
        );
        _loadAuthorizations(); // Refresh the list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reject authorization: $e')),
        );
      }
    }
  }

  void _generateReceipt(String dealId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReceiptGeneratorPage(dealAuthorizationId: dealId),
      ),
    );
  }

  Future<void> _deleteDealAuthorization(String dealId) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Deal Authorization'),
        content: const Text(
          'Are you sure you want to delete this deal authorization? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _discountService.deleteDealAuthorization(dealId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deal authorization deleted successfully'),
            backgroundColor: kBrandGreen,
          ),
        );
        _loadAuthorizations(); // Refresh the list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showRejectDialog(String dealId) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Authorization'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please provide a reason for rejection:'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: 'Reason for rejection...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isNotEmpty) {
                Navigator.of(context).pop();
                _rejectAuthorization(dealId, reason);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<String?> _getLatestDealStatus(String dealId) async {
    try {
      final response = await SupabaseService.instance.client
          .from('deal_authorizations')
          .select('status')
          .eq('id', dealId)
          .maybeSingle();

      return response?['status'] as String?;
    } catch (e) {
      _logger.w('Could not load latest deal status for $dealId: $e');
      return null;
    }
  }

  void _showPOSPaymentConfirmation(DealAuthorization auth) {
    // Verify mounted state and context before attempting to show dialog
    if (!mounted || !context.mounted) {
      return;
    }

    // Guard against stale cards/dialogs for already-processed deals.
    if (auth.status != 'approved') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This deal is already ${auth.status}. Refreshing dashboard...',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      _loadAuthorizations();
      return;
    }

    final memberName = buildMemberDisplayName(
      name: auth.member?.name,
      surname: auth.member?.surname,
      email: auth.member?.email,
    );
    final discountName = auth.discount?.name ?? 'Unknown Deal';
    final amount = auth.amount?.toStringAsFixed(2) ?? '0.00';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kBrandBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.store, color: kBrandBlue, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Verify POS Payment',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: StatefulBuilder(
            builder: (context, setState) {
              final MobileScannerController scannerController =
                  MobileScannerController(detectionTimeoutMs: 1000);
              String? scannedUserId;
              String? scanError;
              bool isVerified = false;
              bool paymentComplete = false;

              Future<void> verifyScannedMember(String rawValue) async {
                try {
                  final decoded = jsonDecode(rawValue);
                  if (decoded is! Map<String, dynamic>) {
                    throw const FormatException('Invalid QR format');
                  }

                  final type = decoded['type'] as String?;
                  if (type != 'user_qr') {
                    throw const FormatException('This QR is not a member QR code.');
                  }

                  final userId = decoded['user_id'] as String?;
                  if (userId == null || userId.isEmpty) {
                    throw const FormatException('No member ID found in QR.');
                  }

                  final profileResponse = await SupabaseService.instance.client
                      .from('profiles')
                      .select('id, name, surname, email, subscription')
                      .eq('id', userId)
                      .maybeSingle();

                  if (profileResponse == null) {
                    throw const FormatException('Member profile not found.');
                  }

                  final qrResponse = await SupabaseService.instance.client
                      .from('user_qr_codes')
                      .select('is_active, expires_at')
                      .eq('user_id', userId)
                      .eq('is_active', true)
                      .order('created_at', ascending: false)
                      .limit(1);

                  final isActive = profileResponse['subscription'] == 'active' &&
                      qrResponse.isNotEmpty;
                  if (!isActive) {
                    throw const FormatException(
                      'This member is not active and cannot complete the sale.',
                    );
                  }

                  setState(() {
                    scannedUserId = userId;
                    isVerified = true;
                    scanError = null;
                    paymentComplete = false;
                  });
                } catch (e) {
                  setState(() {
                    scanError = e.toString().replaceFirst('Exception: ', '').replaceFirst('FormatException: ', '');
                    scannedUserId = null;
                    isVerified = false;
                    paymentComplete = false;
                  });
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Scan the member QR code and confirm the payment once the member profile is active.',
                    style: TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 250,
                      child: MobileScanner(
                        controller: scannerController,
                        onDetect: (capture) async {
                          for (final barcode in capture.barcodes) {
                            final rawValue = barcode.rawValue;
                            if (rawValue == null || rawValue.isEmpty) continue;
                            await scannerController.stop();
                            await verifyScannedMember(rawValue);
                            return;
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (scanError != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              scanError!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isVerified && scannedUserId != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Member:'),
                              Flexible(
                                child: Text(
                                  memberName,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Deal:'),
                              Flexible(
                                child: Text(
                                  discountName,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Amount:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'R$amount',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: kBrandGreen,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            value: paymentComplete,
                            onChanged: (value) {
                              setState(() {
                                paymentComplete = value ?? false;
                              });
                            },
                            title: const Text('Payment complete'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              try {
                final user = SupabaseService.instance.getCurrentUser();
                if (user == null) return;

                final latestStatus = await _getLatestDealStatus(auth.id);
                if (!mounted || !context.mounted) return;

                if (latestStatus == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Could not verify latest deal status. Please try again.',
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  _loadAuthorizations();
                  return;
                }

                if (latestStatus == 'completed') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'This deal is already completed. No changes applied.',
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  _loadAuthorizations();
                  return;
                }

                if (latestStatus != 'approved') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Deal status changed to "$latestStatus". Refreshing...',
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  _loadAuthorizations();
                  return;
                }

                await _dealService.cancelPOSPayment(
                  dealId: auth.id,
                  memberId: auth.memberId,
                  reason: 'Payment unsuccessful at POS terminal',
                );

                if (mounted && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Payment marked as unsuccessful. Member has been notified.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  _loadAuthorizations();
                }
              } catch (e) {
                if (mounted && context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            icon: const Icon(Icons.close),
            label: const Text('Payment Unsuccessful'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              try {
                final user = SupabaseService.instance.getCurrentUser();
                if (user == null) return;

                final latestStatus = await _getLatestDealStatus(auth.id);
                if (!mounted || !context.mounted) return;

                if (latestStatus == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Could not verify latest deal status. Please try again.',
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  _loadAuthorizations();
                  return;
                }

                if (latestStatus == 'completed') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'This deal is already completed. No changes applied.',
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  _loadAuthorizations();
                  return;
                }

                if (latestStatus != 'approved') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Deal status changed to "$latestStatus". Refreshing...',
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  _loadAuthorizations();
                  return;
                }

                await _dealService.completePOSPayment(
                  dealId: auth.id,
                  trustedPartnerId: user.id,
                );

                if (mounted && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Payment successful! Receipt issued to member.',
                      ),
                      backgroundColor: kBrandGreen,
                    ),
                  );
                  _loadAuthorizations();
                }
              } catch (e) {
                if (mounted && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to complete payment: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.check_circle),
            label: const Text('Confirm Payment'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kBrandGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: BrandedAppBar(
          title: const Text('Deal Authorizations'),
          backgroundColor: kBrandBlue,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            labelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: 14,
            ),
            indicator: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            indicatorPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 8,
            ),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.pending, size: 18),
                    const SizedBox(width: 4),
                    const Flexible(
                      child: Text('Pending', overflow: TextOverflow.ellipsis),
                    ),
                    if (_pendingAuthorizations.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_pendingAuthorizations.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 18),
                    SizedBox(width: 4),
                    Flexible(
                      child: Text('Approved', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              const Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long, size: 18),
                    SizedBox(width: 4),
                    Flexible(
                      child: Text('Receipts', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadAuthorizations,
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  TabBarView(
                    children: [
                      _buildAuthorizationList(_pendingAuthorizations, 'pending'),
                      _buildAuthorizationList(_approvedAuthorizations, 'approved'),
                      _buildReceiptsTab(),
                    ],
                  ),
                  // Subtle top progress bar shown during background realtime
                  // refreshes so the user sees activity without the list
                  // blanking out (fixes the "second deal disappears" bug).
                  if (_isRefreshing)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildAuthorizationList(
    List<DealAuthorization> authorizations,
    String type,
  ) {
    if (authorizations.isEmpty) {
      return _buildEmptyState(type);
    }

    return RefreshIndicator(
      onRefresh: _loadAuthorizations,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: authorizations.length,
        itemBuilder: (context, index) {
          final auth = authorizations[index];
          return _buildAuthorizationCard(auth, type);
        },
      ),
    );
  }

  Widget _buildReceiptsTab() {
    if (_receipts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Receipts Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Receipts will appear here automatically\nafter members complete payments',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAuthorizations,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _receipts.length,
        itemBuilder: (context, index) {
          final receipt = _receipts[index];
          return _buildReceiptCard(receipt);
        },
      ),
    );
  }

  Widget _buildReceiptCard(Map<String, dynamic> receipt) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
          leading: const CircleAvatar(
            backgroundColor: kBrandGreen,
            child: Icon(Icons.receipt, color: Colors.white),
          ),
        title: Text(
          receipt['business_name'] ?? 'Business',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Receipt: ${receipt['receipt_number'] ?? 'N/A'}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Member: ${receipt['member_name'] ?? 'N/A'}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              _formatReceiptDate(receipt['created_at']),
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'R${_formatReceiptAmount(receipt['amount'])}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: kBrandGreen,
              ),
            ),
            const SizedBox(height: 4),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
        onTap: () => _showReceiptDetails(receipt),
      ),
    );
  }

  String _formatReceiptDate(String? dateString) {
    if (dateString == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateString).toLocal();
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }

  String _formatReceiptAmount(dynamic amount) {
    if (amount == null) return '0.00';
    try {
      final double value = amount is String
          ? double.parse(amount)
          : amount.toDouble();
      return value.toStringAsFixed(2);
    } catch (e) {
      return '0.00';
    }
  }

  void _showReceiptDetails(Map<String, dynamic> receipt) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.receipt_long, color: kBrandGreen),
            SizedBox(width: 8),
            Text('Receipt Details'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildReceiptDetailRow(
                'Receipt Number',
                receipt['receipt_number'] ?? 'N/A',
              ),
              const Divider(),
              _buildReceiptDetailRow(
                'Business',
                receipt['business_name'] ?? 'N/A',
              ),
              _buildReceiptDetailRow(
                'Discount',
                receipt['discount_name'] ?? 'N/A',
              ),
              const Divider(),
              _buildReceiptDetailRow(
                'Amount',
                'R${_formatReceiptAmount(receipt['amount'])}',
              ),
              _buildReceiptDetailRow(
                'Payment Method',
                (receipt['payment_method'] as String?)?.toUpperCase() ?? 'N/A',
              ),
              // Show note for in-store POS payments
              if ((receipt['payment_method'] as String?) == 'pos') ...[
                _buildReceiptDetailRow('Note', 'in-store payment'),
              ],
              const Divider(),
              _buildReceiptDetailRow(
                'Date',
                _formatReceiptDate(receipt['created_at']),
              ),
              const Divider(),
              _buildReceiptDetailRow('Member', receipt['member_name'] ?? 'N/A'),
              _buildReceiptDetailRow(
                'Contact',
                receipt['member_phone'] ?? 'N/A',
              ),
              _buildReceiptDetailRow('Email', receipt['member_email'] ?? 'N/A'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  Widget _buildAuthorizationCard(DealAuthorization auth, String type) {
    final memberName = buildMemberDisplayName(
      name: auth.member?.name,
      surname: auth.member?.surname,
      email: auth.member?.email,
    );
    final discountName = auth.discount?.name ?? 'Unknown Deal';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        memberName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        discountName,
                        style: TextStyle(color: Colors.grey.shade600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(type),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    type.toUpperCase(),
                    style: TextStyle(
                      // Use dark text on the yellow pending badge for legibility
                      color: type == 'pending' ? kBrandBlue : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.payment, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'R${auth.amount?.toStringAsFixed(2) ?? 'N/A'}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 16),
                Icon(
                  auth.paymentMethod == 'in_app'
                      ? Icons.phone_android
                      : Icons.store,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    auth.paymentMethod == 'in_app'
                        ? 'In-App Payment'
                        : 'In-Store Payment',
                    style: TextStyle(color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (auth.notes != null && auth.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Notes: ${auth.notes}',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            if (type == 'pending') _buildPendingActions(auth.id),
            if (type == 'approved') _buildApprovedActions(auth),
            if (type == 'completed') _buildCompletedActions(auth),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingActions(String dealId) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _approveAuthorization(dealId),
                icon: const Icon(Icons.check),
                label: const Text('Approve'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandGreen,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showRejectDialog(dealId),
                icon: const Icon(Icons.close),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _deleteDealAuthorization(dealId),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              side: BorderSide(color: Colors.grey.shade400),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildApprovedActions(DealAuthorization auth) {
    // Check if deal was cancelled/rejected by member
    if (auth.status == 'rejected') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.cancel, size: 20, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                auth.rejectionReason ?? 'Cancelled by member',
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    // Check if payment has been completed
    final bool paymentCompleted =
        auth.paymentCompletedAt != null ||
        auth.completedAt != null ||
        auth.status == 'completed';

    if (paymentCompleted) {
      // Payment completed - show success message with payment method
      final bool isPOS = auth.paymentMethod == 'pos';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 20, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isPOS
                    ? 'Payment completed. Receipt generated and issued to member.'
                    : 'In-app payment received. Receipt generated automatically.',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Payment not completed
    // For in-app: show waiting message with delete option
    // For in-store (POS): show a Paid button the partner can tap after member pays on POS
    if (auth.paymentMethod == 'in_app') {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.hourglass_empty,
                  size: 20,
                  color: kBrandYellow,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Waiting for member to complete payment',
                    style: TextStyle(
                      color: kBrandBlue,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _deleteDealAuthorization(auth.id),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
                side: BorderSide(color: Colors.grey.shade400),
              ),
            ),
          ),
        ],
      );
    }

    // POS flow: show Paid button with delete option
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showPOSPaymentConfirmation(auth),
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Member Paid'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandBlue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _deleteDealAuthorization(auth.id),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              side: BorderSide(color: Colors.grey.shade400),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedActions(DealAuthorization auth) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _generateReceipt(auth.id),
            icon: const Icon(Icons.receipt),
            label: const Text('Generate Receipt'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kBrandBlue,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String type) {
    final title = switch (type) {
      'pending' => 'No Pending Authorizations',
      'approved' => 'No Approved Authorizations',
      _ => 'No Authorizations',
    };

    final message = switch (type) {
      'pending' => 'New authorization requests will appear here',
      'approved' =>
        'Approved deals will appear here.\nReceipts are generated automatically after payment.',
      _ => 'Authorizations will appear here',
    };

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    return switch (status) {
      'pending' => kBrandYellow,
      'approved' => kBrandBlue,
      'completed' => kBrandGreen,
      _ => Colors.grey,
    };
  }
}
