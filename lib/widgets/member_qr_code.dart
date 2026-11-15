import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

import '../services/qr_code_service.dart';
import '../services/supabase_service.dart';
import 'custom_qr_code.dart';

/// Keeps the displayed code registered on the server, including inside dialogs.
class MemberQrCode extends StatefulWidget {
  const MemberQrCode({
    super.key,
    required this.size,
    this.logoAssetPath = 'assets/heart_flag.png',
  });

  final double size;
  final String logoAssetPath;

  @override
  State<MemberQrCode> createState() => _MemberQrCodeState();
}

class _MemberQrCodeState extends State<MemberQrCode>
    with WidgetsBindingObserver {
  final Logger _logger = Logger();
  Timer? _timer;
  Timer? _expiryTimer;
  String? _payload;
  String? _error;
  bool _refreshing = false;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_resumed) unawaited(_refresh());
    });
    unawaited(_refresh(force: true));
  }

  Future<void> _refresh({bool force = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) throw StateError('Sign in to display your member QR.');
      final payload = await QrCodeService().refreshMemberQrCode(
        user.id,
        force: force,
      );
      if (!mounted) return;
      _expiryTimer?.cancel();
      final expiry = payload == null
          ? null
          : QrCodeService.memberQrExpiry(payload);
      if (expiry != null) {
        _expiryTimer = Timer(expiry.difference(DateTime.now().toUtc()), () {
          if (!mounted) return;
          setState(() {
            _payload = null;
            _error = 'Your QR expired. Check your connection and retry.';
          });
          if (_resumed) unawaited(_refresh());
        });
      }
      setState(() {
        _payload = payload;
        _error = payload == null
            ? 'No active member QR. Refresh your membership and try again.'
            : null;
      });
    } catch (error, stackTrace) {
      _logger.e(
        'Member QR refresh failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _payload = null;
        _error = 'Unable to refresh your QR. Check your connection and retry.';
      });
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _expiryTimer?.cancel();
    setState(() {
      _resumed = state == AppLifecycleState.resumed;
      _payload = null;
    });
    if (_resumed) unawaited(_refresh(force: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: !_resumed
          ? const Center(child: Icon(Icons.lock_outline))
          : payload != null && QrCodeService.isFreshMemberQrCode(payload)
          ? CustomQrCode(
              data: payload,
              size: widget.size,
              logoAssetPath: widget.logoAssetPath,
            )
          : Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(
                          onPressed: () => _refresh(force: true),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
            ),
    );
  }
}
