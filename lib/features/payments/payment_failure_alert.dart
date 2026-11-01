import 'package:flutter/material.dart';
import '../../services/notification_service.dart';
import '../../models/notification.dart';

/// Widget that displays payment failure alerts prominently
/// Shows when user has a payment_failed subscription status
class PaymentFailureAlert extends StatefulWidget {
  final String userId;
  final VoidCallback? onUpdatePaymentMethod;

  const PaymentFailureAlert({
    super.key,
    required this.userId,
    this.onUpdatePaymentMethod,
  });

  @override
  State<PaymentFailureAlert> createState() => _PaymentFailureAlertState();
}

class _PaymentFailureAlertState extends State<PaymentFailureAlert> {
  final NotificationService _notificationService = NotificationService();
  NotificationModel? _paymentFailureNotification;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkPaymentFailure();
  }

  Future<void> _checkPaymentFailure() async {
    try {
      final notification = await _notificationService.getLatestPaymentFailure(
        widget.userId,
      );
      if (mounted) {
        setState(() {
          _paymentFailureNotification = notification;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _dismissAlert() async {
    if (_paymentFailureNotification != null) {
      try {
        await _notificationService.markNotificationAsRead(
          _paymentFailureNotification!.id,
        );
        if (mounted) {
          setState(() {
            _paymentFailureNotification = null;
          });
        }
      } catch (e) {
        // Ignore error
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _paymentFailureNotification == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade300, width: 2),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade700, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _paymentFailureNotification!.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: _dismissAlert,
                color: Colors.red.shade700,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _paymentFailureNotification!.message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.red.shade800,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _dismissAlert();
                    widget.onUpdatePaymentMethod?.call();
                  },
                  icon: const Icon(Icons.payment, size: 20),
                  label: const Text('Update Payment Method'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _dismissAlert,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                ),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Banner widget for payment failure - can be shown at top of pages
class PaymentFailureBanner extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  const PaymentFailureBanner({super.key, this.onTap, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Payment failed. Tap to update payment method.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }
}
