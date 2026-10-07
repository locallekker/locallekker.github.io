import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';

bool get isGooglePayBrowserCheckoutEnabled =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android &&
    dotenv.env['PAYSTACK_GOOGLE_PAY_ENABLED']?.trim().toLowerCase() == 'true';

/// Opens the existing transaction in a wallet-capable browser, not a WebView.
class BrowserPaymentOption extends StatefulWidget {
  const BrowserPaymentOption({super.key, required this.authorizationUrl});

  final String authorizationUrl;

  @override
  State<BrowserPaymentOption> createState() => _BrowserPaymentOptionState();
}

class _BrowserPaymentOptionState extends State<BrowserPaymentOption> {
  final Logger _logger = Logger();
  bool _opening = false;
  String? _error;

  Future<void> _openCheckout() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final uri = Uri.tryParse(widget.authorizationUrl);
      if (uri == null ||
          uri.scheme != 'https' ||
          !(uri.host == 'paystack.com' || uri.host.endsWith('.paystack.com'))) {
        throw StateError('Invalid Paystack checkout URL');
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        throw StateError('Browser could not open checkout');
      }
    } catch (error, stackTrace) {
      _logger.e(
        'Unable to open browser payment checkout',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _error =
              'Could not open your browser. Try again or pay by card below.';
        });
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: _opening ? null : _openCheckout,
              icon: const Icon(Icons.open_in_browser),
              label: Text(_opening ? 'Opening browser...' : 'Pay in browser'),
            ),
            const Text(
              'For Google Pay, use Chrome with an eligible card. '
              'Return here after paying; we will verify your payment.',
              textAlign: TextAlign.center,
            ),
            if (_error != null)
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
