import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/paystack_service.dart';

class PaymentMethodWebViewPage extends StatefulWidget {
  final String authorizationUrl;
  final String userId;
  final String userEmail;

  const PaymentMethodWebViewPage({
    super.key,
    required this.authorizationUrl,
    required this.userId,
    required this.userEmail,
  });

  @override
  State<PaymentMethodWebViewPage> createState() =>
      _PaymentMethodWebViewPageState();
}

class _PaymentMethodWebViewPageState extends State<PaymentMethodWebViewPage> {
  final Logger _logger = Logger();
  final PaystackService _paystackService = PaystackService();
  late final WebViewController _controller;
  bool _loading = true;
  bool _processingPayment = false;
  bool _showingSuccess = false;

  String get _callbackUrl {
    final webCallbackUrl = dotenv.env['PAYSTACK_CALLBACK_URL'];
    return webCallbackUrl ?? 'locallekker://payment/callback';
  }

  bool _isPaystackSuccessUrl(String url) {
    final isPaystackUrl =
        url.contains('checkout.paystack.com') || url.contains('paystack.com');
    final hasSuccessIndicator =
        url.contains('success') ||
        url.contains('trxref=') ||
        url.contains('reference=') ||
        url.contains('/receipt') ||
        url.contains('status=success');

    _logger.d(
      'Checking URL - isPaystackUrl: $isPaystackUrl, hasSuccessIndicator: $hasSuccessIndicator',
    );
    return isPaystackUrl && hasSuccessIndicator;
  }

  Future<void> _handlePaymentSuccess(String url) async {
    if (_processingPayment) {
      _logger.i('Already processing payment, skipping duplicate call');
      return;
    }

    _logger.i('=== PAYMENT METHOD ADDITION SUCCESS ===');
    _logger.i('UserId: ${widget.userId}');
    _logger.i('URL: $url');

    setState(() {
      _processingPayment = true;
      _showingSuccess = true;
    });

    try {
      String? reference;
      final uri = Uri.parse(url);
      reference =
          uri.queryParameters['reference'] ?? uri.queryParameters['trxref'];

      if (reference == null) {
        _logger.w('No reference found in URL, attempting to extract from path');
        final pathSegments = uri.pathSegments;
        if (pathSegments.isNotEmpty) {
          reference = pathSegments.last;
        }
      }

      if (reference == null || reference.isEmpty) {
        throw Exception(
          'Could not extract payment reference from callback URL',
        );
      }

      _logger.i('Payment reference: $reference');

      final paymentDetails = await _paystackService.verifyTransaction(
        reference,
      );

      if (paymentDetails == null) {
        throw Exception('Failed to verify transaction');
      }

      final authorizationData = paymentDetails['authorization'];
      if (authorizationData == null) {
        throw Exception('No authorization data in payment response');
      }

      final authorizationCode = authorizationData['authorization_code'];
      if (authorizationCode == null || authorizationCode.isEmpty) {
        throw Exception('No authorization code in payment response');
      }

      final cardDetails = {
        'card_type': authorizationData['card_type'] ?? 'card',
        'last4': authorizationData['last4'] ?? '****',
        'exp_month': authorizationData['exp_month'],
        'exp_year': authorizationData['exp_year'],
        'bank': authorizationData['bank'],
        'brand': authorizationData['brand'],
      };

      _logger.i(
        'Saving payment method with authorization code: $authorizationCode',
      );

      await _paystackService.addPaymentMethod(
        widget.userId,
        authorizationCode,
        cardDetails,
      );

      final existingMethods = await _paystackService.getSavedPaymentMethods(
        widget.userId,
      );
      if (existingMethods.length == 1) {
        _logger.i('First payment method added, setting as primary');
        await _paystackService.setPrimaryPaymentMethod(
          widget.userId,
          authorizationCode,
        );
      }

      _logger.i('Payment method added successfully');

      // Also save Paystack customer_code on profile to surface saved card UI
      final customer = paymentDetails['customer'];
      final customerCode = customer != null
          ? (customer['customer_code'] as String?)
          : null;
      if (customerCode != null && customerCode.isNotEmpty) {
        try {
          await _paystackService.savePaystackCustomerCode(
            userId: widget.userId,
            customerCode: customerCode,
          );
        } catch (e) {
          _logger.w('Failed to save customer_code: $e');
        }
      }

      if (mounted) {
        setState(() {
          _showingSuccess = true;
          _processingPayment = true;
        });

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          setState(() {
            _processingPayment = false;
          });
          Navigator.of(context).pop(true);
        }
      }
    } catch (e, stackTrace) {
      _logger.e('Error processing payment method: $e');
      _logger.e('Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _processingPayment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add payment method: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        Navigator.of(context).pop(false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _loading = true);
            _logger.d('Page started loading: $url');
          },
          onPageFinished: (url) async {
            setState(() => _loading = false);
            _logger.i('=== PAGE FINISHED LOADING ===');
            _logger.i('URL: $url');

            if (_isPaystackSuccessUrl(url)) {
              _logger.i('Detected Paystack success URL: $url');
              await _handlePaymentSuccess(url);
              return;
            }

            try {
              final pageTitle = await _controller.getTitle();
              _logger.i('WebView page title: $pageTitle');
              if (pageTitle != null &&
                  pageTitle.toLowerCase().contains('payment successful')) {
                _logger.i(
                  'Detected Paystack success by page title: $pageTitle',
                );
                await _handlePaymentSuccess(url);
                return;
              }
            } catch (e) {
              _logger.w('Could not get WebView page title: $e');
            }

            if (url.contains('paystack.com')) {
              // Override window.open() to redirect 3DS popup navigation into
              // this WebView window (same fix as paystack_webview_page.dart).
              try {
                await _controller.runJavaScript(r'''
                  (function() {
                    if (window.__llOpenOverride) return;
                    window.__llOpenOverride = true;
                    window.open = function(url, target, features) {
                      if (url && url !== '' && url !== 'about:blank') {
                        window.location.href = url;
                        return { focus: function(){}, close: function(){}, location: { href: url } };
                      }
                    };
                  })();
                ''');
                _logger.d('Injected window.open override for 3DS popup handling');
              } catch (e) {
                _logger.w('Could not inject window.open override: $e');
              }
              try {
                _logger.d('Checking page content for success indicators...');
                final successScript = '''
                  (function() {
                    const bodyText = document.body.innerText.toLowerCase();
                    const hasPaymentSuccessful = bodyText.includes("payment successful");
                    const hasYouPaid = bodyText.includes("you paid");
                    const hasTransactionSuccessful = bodyText.includes("transaction successful");
                    const hasSuccessClass = document.querySelector(".success") !== null;
                    const hasCheckmark = document.querySelector('[class*="check"]') !== null || 
                                         document.querySelector('[class*="success"]') !== null;
                    
                    return hasPaymentSuccessful || hasYouPaid || hasTransactionSuccessful || 
                           hasSuccessClass || hasCheckmark;
                  })()
                ''';

                final hasSuccessButton = await _controller
                    .runJavaScriptReturningResult(successScript);
                _logger.i(
                  'Enhanced page content check result: $hasSuccessButton',
                );

                if (hasSuccessButton == true ||
                    hasSuccessButton.toString() == 'true') {
                  _logger.i(
                    '✅ Detected success by enhanced page content analysis',
                  );
                  await _handlePaymentSuccess(url);
                  return;
                }
              } catch (e) {
                _logger.w('Could not check page content: $e');
              }
            }

            _logger.d('No success indicators detected on this page');
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            _logger.d('Navigation request: $url');

            if (url.startsWith(_callbackUrl)) {
              _logger.i('Detected callback URL: $url');
              _handlePaymentSuccess(url);
              return NavigationDecision.prevent;
            }

            if (_isPaystackSuccessUrl(url)) {
              _logger.i('Detected success URL in navigation: $url');
              _handlePaymentSuccess(url);
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizationUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Add Payment Method'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _processingPayment
              ? null
              : () {
                  Navigator.of(context).pop(false);
                },
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_processingPayment)
            Container(
              color: Colors.black54,
              child: Center(
                // Make the overlay card scrollable and constrain its max size
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width - 48,
                      maxHeight: MediaQuery.of(context).size.height * 0.8,
                    ),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_showingSuccess) ...[
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 64,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Payment Method Added!',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Your payment method has been saved successfully.',
                                textAlign: TextAlign.center,
                              ),
                            ] else ...[
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              const Text(
                                'Processing...',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Please wait while we save your payment method.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
