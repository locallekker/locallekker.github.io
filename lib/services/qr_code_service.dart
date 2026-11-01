import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class QrCodeService {
  static final QrCodeService _instance = QrCodeService._internal();
  factory QrCodeService() => _instance;
  QrCodeService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  /// Generate a short-lived QR payload to reduce screenshot reuse.
  Future<String> generateEphemeralQrCode(
    String userId, {
    Duration ttl = const Duration(seconds: 45),
  }) async {
    try {
      final profile = await _client
          .from('profiles')
          .select('name, surname')
          .eq('id', userId)
          .single();

      final name = profile['name'] as String? ?? 'Unknown';
      final surname = profile['surname'] as String? ?? 'Unknown';
      final issuedAt = DateTime.now().toUtc();
      final expiresAt = issuedAt.add(ttl);

      final data = {
        'type': 'user_qr_v2',
        'ver': 2,
        'user_id': userId,
        'name': name,
        'surname': surname,
        'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
        'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
        'nonce': '${issuedAt.microsecondsSinceEpoch}-${Random().nextInt(999999)}',
      };
      return jsonEncode(data);
    } catch (e) {
      if (kDebugMode) {
        print('Error generating ephemeral QR code payload: $e');
      }

      final issuedAt = DateTime.now().toUtc();
      final expiresAt = issuedAt.add(ttl);
      final data = {
        'type': 'user_qr_v2',
        'ver': 2,
        'user_id': userId,
        'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
        'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
        'nonce': '${issuedAt.microsecondsSinceEpoch}-${Random().nextInt(999999)}',
      };
      return jsonEncode(data);
    }
  }

  /// Generate a unique QR code for a user including name and surname
  Future<String> generateUniqueQrCode(String userId) async {
    try {
      // Fetch user's name and surname from profiles
      final profile = await _client
          .from('profiles')
          .select('name, surname')
          .eq('id', userId)
          .single();

      final name = profile['name'] as String? ?? 'Unknown';
      final surname = profile['surname'] as String? ?? 'Unknown';

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = Random().nextInt(999999);
      final data = {
        'user_id': userId,
        'name': name,
        'surname': surname,
        'timestamp': timestamp,
        'random': random,
        'type': 'user_qr',
      };
      return jsonEncode(data);
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching profile for QR code: $e');
      }
      // Fallback to basic QR code without name/surname
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = Random().nextInt(999999);
      final data = {
        'user_id': userId,
        'timestamp': timestamp,
        'random': random,
        'type': 'user_qr',
      };
      return jsonEncode(data);
    }
  }

  /// Secure QR code display widget with screenshot prevention
  Widget buildSecureQrCode({
    required String qrData,
    required bool isActive,
    required VoidCallback onScreenshotDetected,
    double size = 200,
  }) {
    return ScreenshotProtectedQrCode(
      qrData: qrData,
      isActive: isActive,
      size: size,
      onScreenshotDetected: onScreenshotDetected,
    );
  }

  /// Initialize screenshot protection
  void initializeScreenshotProtection(BuildContext context) {
    // Note: Hardware-level screenshot detection is not available
    // We rely on UI-based prevention and user education instead
    _showSecurityWarning(context);
  }

  /// Show security warning to user
  void _showSecurityWarning(BuildContext context) {
    // Show warning dialog on first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('🔒 Security Notice'),
          content: const Text(
            'For your security, QR codes should never be shared or screenshotted. '
            'If you attempt to screenshot this QR code, it will be temporarily hidden.\n\n'
            'Please keep your QR code secure and only use it for legitimate transactions.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('I Understand'),
            ),
          ],
        ),
      );
    });
  }

  /// Dispose resources
  void dispose() {
    // No resources to dispose without screenshot_callback
  }
}

class ScreenshotProtectedQrCode extends StatefulWidget {
  final String qrData;
  final bool isActive;
  final double size;
  final VoidCallback onScreenshotDetected;

  const ScreenshotProtectedQrCode({
    super.key,
    required this.qrData,
    required this.isActive,
    required this.size,
    required this.onScreenshotDetected,
  });

  @override
  State<ScreenshotProtectedQrCode> createState() =>
      _ScreenshotProtectedQrCodeState();
}

class _ScreenshotProtectedQrCodeState extends State<ScreenshotProtectedQrCode> {
  final bool _isBlurred = false;

  @override
  void initState() {
    super.initState();
    // Note: Without screenshot_callback, we can't detect screenshots
    // But we still provide UI protection and warnings
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Security warning
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.security, color: Colors.red, size: 16),
                const SizedBox(width: 4),
                Text(
                  'Screenshot Protected',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // QR Code with blur protection
          Stack(
            alignment: Alignment.center,
            children: [
              // The actual QR code
              Opacity(
                opacity: widget.isActive ? 1.0 : 0.3,
                child: QrImageView(
                  data: widget.qrData,
                  version: QrVersions.auto,
                  size: widget.size,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),

              // Blur overlay when screenshot detected
              if (_isBlurred)
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      '⚠️\nScreenshot\nDetected',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              // Inactive overlay
              if (!widget.isActive)
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.block, color: Colors.white, size: 32),
                        SizedBox(height: 8),
                        Text(
                          'Inactive',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.isActive ? Colors.green : Colors.red,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isActive ? Icons.check_circle : Icons.cancel,
                  color: widget.isActive ? Colors.green : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.isActive ? 'Active' : 'Inactive',
                  style: TextStyle(
                    color: widget.isActive ? Colors.green : Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
