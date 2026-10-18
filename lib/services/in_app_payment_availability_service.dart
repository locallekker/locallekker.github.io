import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

import 'supabase_service.dart';

/// Decides whether members may choose "Pay through App" for a deal, based on
/// whether the partner has loaded banking details (Paystack subaccount).
///
/// Fails open: if the check itself errors, in-app payment stays available and
/// the existing payment-time subaccount check in DealApprovalPopupService
/// still applies, so Paystack payments are never blocked by this service.
class InAppPaymentAvailabilityService {
  static final InAppPaymentAvailabilityService _instance =
      InAppPaymentAvailabilityService._internal();
  factory InAppPaymentAvailabilityService() => _instance;
  InAppPaymentAvailabilityService._internal();

  static const String unavailableErrorCode = 'IN_APP_PAYMENT_UNAVAILABLE';
  static const Duration _cacheTtl = Duration(minutes: 5);

  final Logger _logger = Logger();
  final Map<String, _CachedAvailability> _cache = {};

  static bool isUnavailableError(Object error) =>
      error.toString().contains(unavailableErrorCode);

  /// Synchronous cache lookup, or null when not yet checked.
  bool? cachedAvailability(String discountId) {
    final cached = _cache[discountId];
    if (cached == null) return null;
    if (DateTime.now().difference(cached.checkedAt) > _cacheTtl) return null;
    return cached.available;
  }

  Future<bool> isAvailableForDiscount(String discountId) async {
    if (discountId.isEmpty) return true;

    final cached = cachedAvailability(discountId);
    if (cached != null) return cached;

    try {
      final result = await SupabaseService.instance.client.rpc(
        'discount_accepts_in_app_payment',
        params: {'p_discount_id': discountId},
      );
      final available = result != false;
      _cache[discountId] = _CachedAvailability(available, DateTime.now());
      return available;
    } catch (e) {
      _logger.w('In-app payment availability check failed: $e');
      return true;
    }
  }

  void markUnavailable(String discountId) {
    if (discountId.isEmpty) return;
    _cache[discountId] = _CachedAvailability(false, DateTime.now());
  }

  Future<void> notifyPartner(String discountId) async {
    if (discountId.isEmpty) return;
    try {
      await SupabaseService.instance.client.rpc(
        'notify_tp_in_app_payment_unavailable',
        params: {'p_discount_id': discountId},
      );
    } catch (e) {
      _logger.w('Could not notify partner about missing banking details: $e');
    }
  }

  /// Explains that in-app payment is unavailable and that the member will pay
  /// in store, and lets the partner know (rate-limited server-side).
  Future<void> showUnavailableDialog(
    BuildContext context, {
    required String discountId,
    String? partnerName,
  }) async {
    markUnavailable(discountId);
    await notifyPartner(discountId);
    if (!context.mounted) return;

    final name = (partnerName == null || partnerName.trim().isEmpty)
        ? 'This partner'
        : partnerName.trim();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.store, color: Color(0xFF3C8C44)),
            SizedBox(width: 8),
            Expanded(child: Text('Please pay in store')),
          ],
        ),
        content: Text(
          '$name can\'t accept payments through the app yet. '
          'We\'ve switched your request to Pay in store, so you can pay at '
          'the counter and still get your discount.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3C8C44),
              foregroundColor: Colors.white,
            ),
            child: const Text('OK, pay in store'),
          ),
        ],
      ),
    );
  }
}

class _CachedAvailability {
  final bool available;
  final DateTime checkedAt;
  _CachedAvailability(this.available, this.checkedAt);
}
