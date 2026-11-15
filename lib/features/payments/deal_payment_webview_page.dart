import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:local_lekker/services/navigation_service.dart';
import 'package:local_lekker/services/paystack_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:local_lekker/widgets/browser_payment_option.dart';
import 'package:local_lekker/services/web_checkout.dart';

class DealPaymentWebViewPage extends StatefulWidget {
  final String authorizationUrl;
  final String dealId;
  final String? transactionReference;

  /// When true, the new card saved from this payment will be set as the
  /// member's primary card for future in-app payments and subscription
  /// renewals (overriding the "auto-primary only when none exists" rule).
  final bool makeNewCardPrimary;

  const DealPaymentWebViewPage({
    super.key,
    required this.authorizationUrl,
    required this.dealId,
    this.transactionReference,
    this.makeNewCardPrimary = false,
  });

  @override
  State<DealPaymentWebViewPage> createState() => _DealPaymentWebViewPageState();
}

class _DealPaymentWebViewPageState extends State<DealPaymentWebViewPage>
    with WidgetsBindingObserver {
  final Logger _logger = Logger();
  final SupabaseClient _supabase = Supabase.instance.client;
  // Null on web: webview_flutter has no web implementation, so the checkout
  // is opened in a new tab instead and completion is detected via API
  // polling / Supabase Realtime (both independent of this controller).
  WebViewController? _controller;
  // Stays false on web: there's no WebView page-load lifecycle to clear it.
  bool _loading = !kIsWeb;
  bool _processingPayment = false;
  bool _showingSuccess = false;
  bool _paymentVerified =
      false; // True only after Paystack verification or success handler
  Timer? _successCheckTimer;
  bool _showBlankPageButton = false; // Show center button on blank pages
  bool _checkoutLoaded = false; // True once Paystack checkout page has loaded
  bool _awaitingExternalAuth = false;
  bool _showManualVerify = false;
  bool _paymentDeclined =
      false; // Paystack showed an "unable to process" / risk-block page
  bool _pollingActive = false; // Prevent multiple concurrent polling timers
  bool _apiPollInFlight = false; // Prevent overlapping Paystack verify requests
  bool _successHandlerStarted = false; // Success handler must run only once
  Timer? _manualVerifyTimer;
  Timer? _apiVerifyTimer; // Direct Paystack API polling (most reliable)
  RealtimeChannel? _dealChannel;

  String get _callbackUrl {
    final webCallbackUrl = dotenv.env['PAYSTACK_CALLBACK_URL'];
    return webCallbackUrl ?? 'locallekker://payment/callback';
  }

  bool _isPaystackSuccessUrl(String url) {
    final isPaystackUrl =
        url.contains('checkout.paystack.com') || url.contains('paystack.com');
    // IMPORTANT: Do NOT treat trxref= or reference= as success indicators.
    // Paystack includes these in ALL redirect URLs regardless of payment outcome.
    final hasSuccessIndicator =
        url.contains('status=success') ||
        url.contains('payment-successful') ||
        url.contains('transaction-successful') ||
        url.toLowerCase().contains('payment%20successful');

    _logger.d(
      'URL Check - isPaystackUrl: $isPaystackUrl, hasSuccess: $hasSuccessIndicator, url: $url',
    );

    return isPaystackUrl && hasSuccessIndicator;
  }

  /// Check if a URL is a Paystack redirect/callback (has reference params)
  /// but does NOT necessarily indicate success - needs API verification.
  bool _isPaystackRedirectUrl(String url) {
    return (url.contains('trxref=') || url.contains('reference='));
  }

  String? _extractReferenceFromUrl(String url) {
    try {
      final uri = Uri.parse(url);

      // Try multiple query parameter names
      String? reference =
          uri.queryParameters['reference'] ??
          uri.queryParameters['trxref'] ??
          uri.queryParameters['tx_ref'] ??
          uri.queryParameters['transaction_reference'] ??
          uri.queryParameters['ref'];

      if (reference == null || reference.isEmpty) {
        final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.isNotEmpty) reference = segments.last;
      }

      _logger.d('Extracted reference from URL: $reference (from: $url)');
      return (reference != null && reference.isNotEmpty) ? reference : null;
    } catch (e) {
      _logger.w('Failed to parse reference from URL: $e');
      return null;
    }
  }

  // New: Extract reference from page JavaScript if not in URL
  Future<String?> _extractReferenceFromPage() async {
    try {
      // Try to extract transaction reference from page's JavaScript variables
      final jsExtractScript = '''
        (function() {
          // Common variable names Paystack might use
          if (typeof trxref !== 'undefined') return trxref;
          if (typeof reference !== 'undefined') return reference;
          if (typeof transaction_reference !== 'undefined') return transaction_reference;
          
          // Check window object
          if (window.trxref) return window.trxref;
          if (window.reference) return window.reference;
          if (window.transaction_reference) return window.transaction_reference;
          
          // Try to extract from page text as last resort
          const text = document.body.innerText;
          const refMatch = text.match(/reference[:\\s]+([A-Za-z0-9_-]+)/i);
          if (refMatch && refMatch[1]) return refMatch[1];
          
          return null;
        })()
      ''';

      final result = await _controller!.runJavaScriptReturningResult(
        jsExtractScript,
      );

      if (result.toString().isNotEmpty) {
        final ref = result.toString();
        if (ref != 'null') {
          _logger.i('✅ Extracted reference from page JavaScript: $ref');
          return ref;
        }
      }
    } catch (e) {
      _logger.w('Failed to extract reference from page: $e');
    }
    return null;
  }

  /// Phrases Paystack's hosted checkout shows when the bank or Paystack's
  /// risk engine rejects a charge (e.g. the generic "Unable to process
  /// transaction" screen). Kept specific to avoid false positives.
  static const List<String> _declineIndicators = [
    'unable to process transaction',
    'unable to process your transaction',
    'transaction could not be completed',
    'transaction was not completed',
    'transaction failed',
    'payment could not be completed',
    'this transaction has been declined',
    'card was declined',
    'declined by your bank',
  ];

  /// Surface a clear in-app banner when Paystack declines the deal charge,
  /// re-evaluated on every poll so it clears itself once the member navigates
  /// back to the card form ("Try another card").
  void _evaluateDeclineText(String bodyText) {
    if (!mounted) return;
    if (_paymentVerified || _showingSuccess || _processingPayment) {
      if (_paymentDeclined) setState(() => _paymentDeclined = false);
      return;
    }
    final looksDeclined = _declineIndicators.any(bodyText.contains);
    if (looksDeclined != _paymentDeclined) {
      if (looksDeclined) {
        _logger.w(
          'Detected Paystack decline/risk page — showing member guidance',
        );
      }
      setState(() => _paymentDeclined = looksDeclined);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_checkoutLoaded && !_processingPayment && !_showingSuccess) {
        _awaitingExternalAuth = true;
        _logger.i(
          'App paused during deal payment - marking as awaiting external auth',
        );
      }
    } else if (state == AppLifecycleState.resumed && _awaitingExternalAuth) {
      _awaitingExternalAuth = false;
      _logger.i(
        'App resumed from background - attempting silent payment verification',
      );
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_processingPayment && !_showingSuccess) {
          _silentVerifyPayment();
        }
      });
    }
  }

  /// Silently check if payment is complete without showing UI errors.
  /// Only proceeds to success handler if verification succeeds.
  Future<void> _silentVerifyPayment({String? url}) async {
    if (_processingPayment || _showingSuccess || _paymentVerified) return;

    String? ref = widget.transactionReference;
    if (ref == null && url != null) {
      ref = _extractReferenceFromUrl(url);
    }
    ref ??= await _extractReferenceFromPage();
    ref ??= widget.transactionReference;

    if (ref == null) return;

    _logger.d('Silent verification check for ref: $ref');

    try {
      final verifiedDetails = await PaystackService().verifyTransaction(
        ref,
        dealId: widget.dealId,
      );
      if (verifiedDetails != null) {
        _logger.i('Silent verification: transaction CONFIRMED successful');
        if (mounted && !_processingPayment && !_showingSuccess) {
          await _handlePaymentSuccess(
            url: url,
            verifiedDetails: verifiedDetails,
          );
        }
      } else {
        _logger.d('Silent verification: transaction not yet successful');
        // Do NOT restart polling — let existing polling or realtime listener handle it
      }
    } catch (e) {
      _logger.w('Silent verification error: $e');
      // Do NOT restart polling — avoid loop. Existing polling or realtime listener will catch it.
    }
  }

  /// Listen for deal completion via Supabase Realtime.
  /// When a webhook or server-side process marks the deal as completed,
  /// this fires and navigates the member home immediately.
  void _setupRealtimeDealListener() {
    try {
      _dealChannel = _supabase
          .channel('deal_payment_${widget.dealId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'deal_authorizations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.dealId,
            ),
            callback: (payload) {
              _logger.i('Realtime: deal_authorizations UPDATE detected');
              final newRecord = payload.newRecord;
              if (newRecord['status'] == 'completed') {
                _onRealtimeDealCompleted();
              }
            },
          )
          .subscribe();

      _logger.i('Realtime deal listener active for deal ${widget.dealId}');
    } catch (e) {
      _logger.w('Failed to set up realtime deal listener: $e');
    }
  }

  /// Called when Supabase Realtime detects the deal is now completed.
  void _onRealtimeDealCompleted() {
    if (!mounted || _showingSuccess) return;
    unawaited(_silentVerifyPayment());
  }

  /// Gateway method: verifies the transaction with Paystack API before
  /// proceeding to mark payment as successful. This prevents premature
  /// success detection from URL patterns or page content.
  Future<void> _verifyAndHandlePayment({String? url}) async {
    if (_processingPayment) {
      _logger.w('⚠️ Payment already being processed, ignoring duplicate call');
      return;
    }

    _successCheckTimer?.cancel();

    // Show a processing spinner while we verify
    if (mounted) {
      setState(() {
        _processingPayment = true;
        _showingSuccess = false;
      });
    }

    _logger.i('=== VERIFYING PAYMENT WITH PAYSTACK API ===');
    _logger.i('Deal ID: ${widget.dealId}');

    // Build an ordered, de-duplicated list of candidate references to verify.
    // The stored transaction reference (from initialization) is the most
    // reliable value, so it is ALWAYS tried first. A reference parsed from the
    // current URL/page can be a bogus path segment (e.g. ".../close" yields
    // "close"), which would otherwise cause verification of the WRONG reference
    // and a false "payment not completed" even though the charge succeeded.
    final candidateRefs = <String>[];
    void addCandidate(String? r) {
      if (r != null && r.isNotEmpty && !candidateRefs.contains(r)) {
        candidateRefs.add(r);
      }
    }

    addCandidate(widget.transactionReference);
    if (widget.transactionReference == null) {
      if (url != null) addCandidate(_extractReferenceFromUrl(url));
      addCandidate(await _extractReferenceFromPage());
    }

    if (candidateRefs.isEmpty) {
      _logger.w('❌ No transaction reference found - cannot verify payment yet');
      // No reference at all usually means the card form was not completed yet.
      // Show the quiet manual-verify button instead of an alarming error and
      // let the background API polling keep watching for completion.
      if (mounted) {
        setState(() {
          _processingPayment = false;
          _showManualVerify = true;
        });
      }
      return;
    }

    _logger.i('🔍 Verifying transaction reference candidates: $candidateRefs');

    // Verify with Paystack API. Use progressive backoff with more attempts so a
    // 3DS transaction has time to settle on Paystack's side before we ever
    // declare failure (mirrors the subscription flow). On each attempt we try
    // every candidate reference so the reliable stored reference is always used
    // even when the URL produced a bogus one.
    Map<String, dynamic>? verifiedDetails;
    const retryDelays = [2, 3, 4, 5, 6, 8]; // seconds between attempts
    final maxRetries = retryDelays.length;

    for (
      int attempt = 0;
      attempt < maxRetries && verifiedDetails == null;
      attempt++
    ) {
      for (final candidate in candidateRefs) {
        try {
          final result = await PaystackService().verifyTransaction(
            candidate,
            dealId: widget.dealId,
          );
          if (result != null) {
            _logger.i(
              '✅ Transaction verified as SUCCESS (ref=$candidate) on attempt ${attempt + 1}',
            );
            verifiedDetails = result;
            break;
          }
        } catch (e) {
          _logger.w(
            'Verification attempt ${attempt + 1} (ref=$candidate) failed: $e',
          );
        }
      }
      if (verifiedDetails == null && attempt < maxRetries - 1) {
        await Future.delayed(Duration(seconds: retryDelays[attempt]));
      }
    }

    if (verifiedDetails == null) {
      // Not confirmed yet. The charge may still be settling on Paystack, so we
      // deliberately do NOT show an alarming "payment failed" message — that
      // scared members whose money had already been deducted. Instead we quietly
      // reveal the manual-verify button and keep the background API polling
      // running, which auto-detects success as soon as Paystack confirms it.
      _logger.w(
        '⚠️ Payment not confirmed after $maxRetries attempts - showing manual verify (polling continues)',
      );
      if (kDebugMode) {
        print(
          '⚠️ PAYMENT NOT YET CONFIRMED - refs: $candidateRefs, deal: ${widget.dealId}',
        );
      }
      if (mounted) {
        setState(() {
          _processingPayment = false;
          _showManualVerify = true;
        });
      }
      return;
    }

    // Payment IS verified as successful - now proceed
    _logger.i('✅ Payment VERIFIED as successful, proceeding to record payment');
    await _handlePaymentSuccess(url: url, verifiedDetails: verifiedDetails);
  }

  Future<void> _handlePaymentSuccess({
    String? url,
    Map<String, dynamic>? verifiedDetails,
  }) async {
    if (_successHandlerStarted || !mounted) return;
    if (verifiedDetails == null) {
      _logger.e('Cannot complete a deal without a verified transaction');
      setState(() {
        _processingPayment = false;
        _showManualVerify = true;
      });
      return;
    }
    _successHandlerStarted = true;
    _successCheckTimer?.cancel();
    _apiVerifyTimer?.cancel();
    _manualVerifyTimer?.cancel();
    setState(() {
      _processingPayment = true;
      _showingSuccess = true;
      _paymentVerified = true;
    });
    try {
      final auth = verifiedDetails['authorization'];
      final userId = _supabase.auth.currentUser?.id;
      if (auth is Map &&
          auth['reusable'] == true &&
          auth['authorization_code'] is String &&
          userId != null) {
        final existing = await PaystackService().getSavedPaymentMethods(userId);
        final primary = widget.makeNewCardPrimary ||
            existing.isEmpty ||
            !existing.any((method) => method['is_primary'] == true);
        await PaystackService()
            .addPaymentMethod(userId, auth['authorization_code'], {
              'card_type': auth['card_type'],
              'last4': auth['last4'],
              'exp_month': auth['exp_month'],
              'exp_year': auth['exp_year'],
              'bank': auth['bank'],
              'brand': auth['brand'],
              'is_primary': primary,
            });
      }
      final customer = verifiedDetails['customer'];
      if (userId != null && customer is Map && customer['customer_code'] is String) {
            await PaystackService().savePaystackCustomerCode(
              userId: userId, customerCode: customer['customer_code'],
            );
      }
    } catch (error) {
      _logger.w(
        'Payment is confirmed, but the reusable card could not be saved: $error',
      );
    }
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) await NavigationService().navigateToHomeAfterPayment(context);
  }

  void _startSuccessPolling() {
    // Prevent multiple concurrent polling timers
    if (_pollingActive ||
        _paymentVerified ||
        _processingPayment ||
        _showingSuccess) {
      _logger.d('Skipping polling start — already active or payment handled');
      return;
    }
    _successCheckTimer?.cancel();
    _pollingActive = true;
    int pollCount = 0;
    const maxPolls =
        30; // Poll for 30 seconds to give user time to complete payment

    _successCheckTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      pollCount++;
      _logger.d(
        'Polling for payment completion... attempt $pollCount/$maxPolls',
      );

      if (_processingPayment || _paymentVerified) {
        timer.cancel();
        _pollingActive = false;
        return;
      }

      try {
        // Check current URL for redirect back (has reference param)
        final currentUrl = await _controller!.currentUrl();

        // If URL has explicit success status indicator, verify via API
        if (currentUrl != null && _isPaystackSuccessUrl(currentUrl)) {
          _logger.i('✅ Polling detected success URL: $currentUrl');
          timer.cancel();
          _pollingActive = false;
          await _verifyAndHandlePayment(url: currentUrl);
          return;
        }

        // If URL is a callback redirect with reference, verify via Paystack API
        if (currentUrl != null &&
            _isPaystackRedirectUrl(currentUrl) &&
            currentUrl.startsWith(_callbackUrl)) {
          _logger.i(
            '🔍 Polling detected callback redirect URL with reference: $currentUrl',
          );
          timer.cancel();
          _pollingActive = false;
          await _verifyAndHandlePayment(url: currentUrl);
          return;
        }

        // For non-callback redirect URLs with reference params (e.g. 3DS bank
        // pages), use silent verification to avoid false error messages
        if (currentUrl != null &&
            _isPaystackRedirectUrl(currentUrl) &&
            !currentUrl.contains('paystack.com') &&
            !currentUrl.contains('paystack.co') &&
            !currentUrl.startsWith(_callbackUrl)) {
          _logger.d(
            'Polling detected non-callback redirect with reference - silent check',
          );
          await _silentVerifyPayment(url: currentUrl);
          if (_processingPayment || _showingSuccess) {
            timer.cancel();
            _pollingActive = false;
            return;
          }
        }

        // Check page text for definitive "You paid" or "Payment Successful" from Paystack
        // These are Paystack's actual success page messages (visible text only)
        final bodyTextResult = await _controller!.runJavaScriptReturningResult(
          'document.body.innerText.toLowerCase()',
        );
        final bodyText = bodyTextResult
            .toString()
            .replaceAll(RegExp(r'^["\s]+|["\s]+$'), '')
            .toLowerCase();

        // Only match Paystack's specific success messages (visible user text)
        if (bodyText.contains('you paid') ||
            bodyText.contains('payment successful')) {
          _logger.i('✅ Polling detected definitive success text in page');
          timer.cancel();
          _pollingActive = false;
          await _verifyAndHandlePayment(url: currentUrl);
          return;
        }

        // Detect a decline/risk-block state (Paystack checkout is an SPA, so
        // this renders without a page reload — polling is the reliable catch).
        _evaluateDeclineText(bodyText);
      } catch (e) {
        _logger.w('Polling error: $e');
      }

      if (pollCount >= maxPolls) {
        _logger.w('Polling timed out after ${maxPolls * 2} seconds');
        timer.cancel();
        _pollingActive = false;

        // Show manual verify button as fallback
        if (mounted && !_processingPayment && !_showingSuccess) {
          setState(() => _showManualVerify = true);
          _logger.i('Polling timeout - showing manual verify button');
        }
      }
    });
  }

  Future<void> _handleManualReturn() => _verifyAndHandlePayment();

  /// Periodically verify the transaction reference directly with Paystack API.
  /// This bypasses all WebView content/URL detection and is the most reliable
  /// mechanism — uses the same API call Paystack uses to confirm before
  /// sending their own success email.
  void _startApiVerificationPolling() {
    final ref = widget.transactionReference;
    if (ref == null || ref.isEmpty) {
      _logger.w('No transaction reference for API polling');
      return;
    }

    // Wait 15 seconds before first check (give user time to enter card details)
    Future.delayed(const Duration(seconds: 15), () {
      if (!mounted || _paymentVerified || _processingPayment || _showingSuccess)
        return;

      int apiPollCount = 0;
      const maxApiPolls = 40; // 40 × 8s = ~320 seconds total coverage

      _apiVerifyTimer = Timer.periodic(const Duration(seconds: 8), (
        timer,
      ) async {
        apiPollCount++;
        if (_paymentVerified || _processingPayment || _showingSuccess) {
          timer.cancel();
          return;
        }
        if (_apiPollInFlight) {
          _logger.d(
            'API verify poll #$apiPollCount skipped: previous check still running',
          );
          if (apiPollCount >= maxApiPolls) timer.cancel();
          return;
        }

        _logger.d('API verify poll #$apiPollCount/$maxApiPolls for ref: $ref');

        _apiPollInFlight = true;
        try {
          final result = await PaystackService().verifyTransaction(
            ref,
            dealId: widget.dealId,
          );
          if (result != null && !_paymentVerified && !_processingPayment) {
            _logger.i(
              'API polling: deal payment CONFIRMED successful on attempt $apiPollCount',
            );
            timer.cancel();
            if (mounted) {
              await _handlePaymentSuccess(verifiedDetails: result);
            }
          }
        } catch (e) {
          _logger.d('API verify poll #$apiPollCount failed: $e');
        } finally {
          _apiPollInFlight = false;
        }

        if (apiPollCount >= maxApiPolls) {
          timer.cancel();
          _logger.w(
            'API verification polling timed out after ${maxApiPolls * 8}s',
          );
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _successCheckTimer?.cancel();
    _manualVerifyTimer?.cancel();
    _apiVerifyTimer?.cancel();
    _dealChannel?.unsubscribe();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Listen for deal completion via Supabase Realtime
    _setupRealtimeDealListener();

    // Start direct Paystack API verification polling (most reliable)
    _startApiVerificationPolling();

    // Show manual verify fallback after 45 seconds in case auto-detection fails
    _manualVerifyTimer = Timer(const Duration(seconds: 45), () {
      if (mounted && !_processingPayment && !_showingSuccess) {
        setState(() => _showManualVerify = true);
        _logger.i('Manual verify fallback now visible (45s elapsed)');
      }
    });

    // webview_flutter has no web implementation — navigate this tab to the
    // checkout (a new tab is popup-blocked on iOS Safari) and rely on the
    // API-verification polling and Realtime deal listener above (both already
    // started, both independent of the webview) when the member returns.
    if (kIsWeb) {
      openWebCheckout(widget.authorizationUrl);
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _loading = true;
              // A fresh navigation (e.g. "Try another card") clears any
              // stale decline banner.
              _paymentDeclined = false;
            });
            _logger.d('Page started loading: $url');
          },
          onPageFinished: (url) async {
            setState(() => _loading = false);
            _logger.i('=== PAGE FINISHED LOADING ===');
            _logger.i('URL: $url');

            // Track when the Paystack checkout page has loaded
            if (url.contains('paystack.com') && !_checkoutLoaded) {
              _checkoutLoaded = true;
              _logger.i('Paystack checkout page loaded');
            }

            // Check if page is blank (redirect aftermath or stuck page)
            // Guards: Skip Paystack pages, only check after checkout loaded,
            // and only auto-verify after manual verify timer (45s)
            if (!url.contains('paystack.com') && !url.contains('paystack.co')) {
              try {
                final pageContent = await _controller!
                    .runJavaScriptReturningResult(
                      'document.body.innerText.trim()',
                    );
                final content = pageContent
                    .toString()
                    .replaceAll(RegExp(r'^["\s]+|["\s]+$'), '')
                    .toLowerCase();
                // Active 3DS / verification / loading pages (e.g. the bank's
                // "PAYMENT VERIFICATION" screen) also have very little text but
                // are NOT stuck. Showing the Return Home button over them looks
                // broken and tempts the member to bail out mid-authentication,
                // so treat them as active pages rather than blank/stuck ones.
                const activeKeywords = [
                  'verif',
                  'process',
                  'authenticat',
                  'redirect',
                  'loading',
                  'please wait',
                  'one moment',
                  'secure',
                  '3d',
                  'otp',
                  'pin',
                  'pending',
                  'confirming',
                  'do not close',
                ];
                final looksActive = activeKeywords.any(
                  (k) => content.contains(k),
                );
                if (content.length < 50 && _checkoutLoaded && !looksActive) {
                  setState(() => _showBlankPageButton = true);
                  _logger.w(
                    'Detected potentially blank/stuck page after checkout',
                  );
                  if (_showManualVerify &&
                      widget.transactionReference != null &&
                      !_processingPayment &&
                      !_paymentVerified) {
                    _logger.i(
                      'Blank page with manual verify active - attempting silent verification',
                    );
                    _silentVerifyPayment(url: url);
                    return;
                  }
                } else {
                  setState(() => _showBlankPageButton = false);
                }
              } catch (e) {
                _logger.w('Could not check page content: $e');
              }
            }

            // Check if this is an explicit success URL - verify via API
            if (_isPaystackSuccessUrl(url)) {
              _logger.i('✅ Detected Paystack success URL, verifying: $url');
              _verifyAndHandlePayment(url: url);
              return;
            }

            // Check if URL is a redirect with reference (callback URL)
            // This does NOT mean success - must verify via API
            if (_isPaystackRedirectUrl(url) && url.startsWith(_callbackUrl)) {
              _logger.i('🔍 Detected callback redirect, verifying: $url');
              _verifyAndHandlePayment(url: url);
              return;
            }

            // Override window.open() to redirect 3DS popup navigation into
            // this WebView window. Paystack's hosted checkout opens the bank
            // authorization page via window.open(); webview_flutter blocks
            // popups by default, so without this override Paystack detects
            // the failed popup and navigates to its /close URL which dismisses
            // the WebView before the bank auth page is shown — the new-card
            // 3DS flow then never completes on Paystack even though the bank
            // deducted the money. This mirrors paystack_webview_page.dart.
            if (url.contains('paystack.com') || url.contains('paystack.co')) {
              try {
                await _controller!.runJavaScript(r'''
                  (function() {
                    if (window.__llOpenOverride) return;
                    window.__llOpenOverride = true;

                    function _llNavigate(u) {
                      if (!u || u === '' || u === 'about:blank') return;
                      // Background cookie probe; loading it top-level kills checkout.
                      if (u.indexOf('/cookie-support/') !== -1) return;
                      if (typeof PaystackPopup !== 'undefined') {
                        PaystackPopup.postMessage(u);
                      } else {
                        window.location.href = u;
                      }
                    }

                    window.open = function(url, target, features) {
                      // Always return a truthy fake window so Paystack's
                      // popup-capability probe (window.open('', '_blank'))
                      // succeeds. Without this the first Pay click is seen
                      // as popup-blocked and Paystack resets the card form
                      // instead of opening the 3DS authenticate page.
                      //
                      // IMPORTANT: fakeWin.location uses Object.defineProperty
                      // so that assignments like `fakeWin.location.href = url`
                      // (Paystack's two-step popup approach: open empty popup
                      // then set location) also trigger navigation here.
                      var _navigated = false;
                      var _locHref = url || '';
                      var locObj = {};
                      Object.defineProperty(locObj, 'href', {
                        get: function() { return _locHref; },
                        set: function(newUrl) {
                          _locHref = newUrl;
                          if (!_navigated) {
                            _navigated = true;
                            _llNavigate(newUrl);
                          }
                        },
                        configurable: true
                      });
                      var fakeWin = {
                        focus: function(){},
                        close: function(){},
                        closed: false,
                        location: locObj
                      };
                      // Handle direct URL (single-step window.open approach)
                      if (url && url !== '' && url !== 'about:blank') {
                        _navigated = true;
                        _llNavigate(url);
                      }
                      return fakeWin;
                    };
                  })();
                ''');
                _logger.d(
                  'Injected window.open override for 3DS popup handling (channel-based)',
                );
              } catch (e) {
                _logger.w('Could not inject window.open override: $e');
              }
            }

            // If on Paystack page, start polling for completion
            // (polling will verify via API before declaring success)
            if (url.contains('paystack.com') &&
                !_pollingActive &&
                !_paymentVerified) {
              _logger.i('On Paystack page - starting completion polling');
              _startSuccessPolling();
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            _logger.d('Navigation request: $url');

            // Detect callback URL - verify with Paystack API before treating as success
            if (url.startsWith(_callbackUrl)) {
              _logger.i('Detected callback URL, will verify: $url');
              _verifyAndHandlePayment(url: url);
              return NavigationDecision.prevent;
            }

            // Detect explicit success URL indicators - verify via API
            if (_isPaystackSuccessUrl(url)) {
              _logger.i('Detected success URL in navigation, verifying: $url');
              _verifyAndHandlePayment(url: url);
              return NavigationDecision.prevent;
            }

            // Detect Paystack close/cancel endpoints.
            // Only match Paystack domains to avoid blocking 3DS bank redirect
            // URLs whose path or query params contain 'cancel' or 'close'.
            // If the close URL includes a transaction reference, verify first.
            final isPaystackCloseDomain =
                url.contains('paystack.com') || url.contains('paystack.co');
            if (isPaystackCloseDomain) {
              final lower = url.toLowerCase();
              if (lower.contains('/close') || lower.contains('/cancel')) {
                _logger.w('Detected Paystack close/cancel URL: $url');
                final hasReference =
                    url.contains('trxref=') || url.contains('reference=');
                // Never declare a cancellation without first confirming with the
                // Paystack API. A new-card 3DS flow can pass through a /close
                // endpoint (closing the bank auth window) with no reference in
                // the URL even though the charge already succeeded — this
                // previously showed "Payment cancelled" after money had already
                // been deducted. _verifyAndHandlePayment falls back to the stored
                // transactionReference and only reports failure if the Paystack
                // API confirms the transaction was not successful.
                if (hasReference || widget.transactionReference != null) {
                  _logger.i(
                    'Close URL — verifying with Paystack API before dismissing (refInUrl=$hasReference)',
                  );
                  _verifyAndHandlePayment(url: url);
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Payment cancelled'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  NavigationService().navigateToHomeAfterPayment(context);
                }
                return NavigationDecision.prevent;
              }
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel(
        'PaystackPopup',
        onMessageReceived: (JavaScriptMessage message) {
          // Receives the bank 3DS auth URL from the window.open override.
          // Using a native loadRequest bypasses the JS navigation queue so
          // Paystack's own subsequent window.location assignment cannot win
          // the race and overwrite the navigation to the bank auth page.
          final url = message.message;
          if (_paymentVerified || _showingSuccess) return;
          if (!url.startsWith('http')) return;
          if (url.contains('/cookie-support/')) return;
          _logger.i('PaystackPopup channel: loading 3DS auth URL: $url');
          _controller!.loadRequest(Uri.parse(url));
        },
      );

    // Paystack 3DS relies on third-party cookies, which Android WebView blocks by default.
    final platformController = _controller!.platform;
    if (platformController is AndroidWebViewController) {
      AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ).setAcceptThirdPartyCookies(platformController, true);
    }

    _controller!.loadRequest(Uri.parse(widget.authorizationUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !(_showingSuccess || _processingPayment),
      onPopInvokedWithResult: (didPop, result) {
        // Show message if user tries to navigate back during critical states
        if (!didPop && (_showingSuccess || _processingPayment)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please use the "Return Home" button'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: BrandedAppBar(
          title: const Text('Secure Payment'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: (_processingPayment || _showingSuccess)
                ? null
                : () async {
                    // Confirm cancellation. We deliberately do NOT offer a
                    // "Payment successful" self-report option here: a payment
                    // must only ever be recorded after the Paystack API
                    // confirms a successful transaction for THIS session
                    // (handled automatically by the detectors and the
                    // "Already paid? Tap here to verify" button). Letting a
                    // cancelling member self-declare success previously
                    // recorded completed deals with no actual charge.
                    final choice = await showModalBottomSheet<String>(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Wrap(
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(
                                'Leave payment?',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            ListTile(
                              leading: const Icon(
                                Icons.payment,
                                color: Colors.green,
                              ),
                              title: const Text('Keep paying'),
                              subtitle: const Text(
                                'Return to the payment page',
                              ),
                              onTap: () => Navigator.pop(ctx, 'stay'),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(
                                Icons.close,
                                color: Colors.red,
                              ),
                              title: const Text('Cancel payment'),
                              subtitle: const Text("You won't be charged"),
                              onTap: () => Navigator.pop(ctx, 'cancel'),
                            ),
                          ],
                        ),
                      ),
                    );

                    if (choice == 'cancel' && mounted) {
                      _logger.i('Payment cancelled by user');
                      await NavigationService().navigateToHomeAfterPayment(
                        context,
                      );
                    }
                    // 'stay' or dismissed → remain on the payment page.
                  },
          ),
        ),
        body: Column(
          children: [
            if (isGooglePayBrowserCheckoutEnabled &&
                !_processingPayment &&
                !_showingSuccess)
              BrowserPaymentOption(authorizationUrl: widget.authorizationUrl),
            Expanded(
              child: Stack(
                children: [
                  // On web there is no in-app WebViewController (checkout opened in
                  // a new tab); show a waiting placeholder instead of the WebView.
                  if (kIsWeb && !_showingSuccess)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 24),
                            Text(
                              'Complete your payment in the tab that just opened.\n'
                              'This page will update automatically once payment is confirmed.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Only show WebView when not showing success
                  if (!kIsWeb && !_showingSuccess)
                    Positioned.fill(
                      child: WebViewWidget(controller: _controller!),
                    ),
                  if (_loading && !_processingPayment && !_showingSuccess)
                    const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (_paymentDeclined &&
                      !_processingPayment &&
                      !_showingSuccess)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 16,
                      child: Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.red.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Payment couldn't be processed",
                                      style: TextStyle(
                                        color: Colors.red.shade900,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Your bank or card provider declined this payment, often '
                                'for security reasons after several attempts. You can try a '
                                'different card above, or go back and try again in a few '
                                'minutes. If it keeps happening, contact your bank to '
                                'approve the payment.',
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Go back'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // "Return Home" button for blank/stuck pages only. Anchored to the
                  // bottom so it never overlaps page content (e.g. a bank's
                  // "PAYMENT VERIFICATION" screen) the way a centered button did.
                  if (_showBlankPageButton &&
                      !_processingPayment &&
                      !_showingSuccess)
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 40,
                      child: Center(
                        child: Material(
                          elevation: 8,
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.transparent,
                          child: ElevatedButton(
                            onPressed: _handleManualReturn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 48,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 8,
                            ),
                            child: const Text(
                              'Verify payment',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Subtle fallback button - only appears after 45 seconds if auto-detection hasn't triggered
                  if (!_showingSuccess &&
                      !_processingPayment &&
                      _showManualVerify &&
                      !_showBlankPageButton)
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: TextButton.icon(
                          onPressed: () {
                            _verifyAndHandlePayment();
                          },
                          icon: const Icon(
                            Icons.help_outline,
                            size: 18,
                            color: Colors.grey,
                          ),
                          label: const Text(
                            'Already paid? Tap here to verify',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_processingPayment || _showingSuccess)
                    Container(
                      color: Colors.white,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!_showingSuccess) ...[
                              const CircularProgressIndicator(strokeWidth: 3),
                              const SizedBox(height: 24),
                              const Text(
                                'Processing payment...',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Please wait, do not close this screen or pay again.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ] else ...[
                              Container(
                                width: 80,
                                height: 80,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Payment Successful!',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Your payment has been processed successfully',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Receipt generated automatically',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 48),
                              ElevatedButton.icon(
                                onPressed: _paymentVerified
                                    ? () async {
                                        _logger.i(
                                          'Proceed to Home tapped after verified payment',
                                        );
                                        await NavigationService()
                                            .navigateToHomeAfterPayment(
                                              context,
                                            );
                                      }
                                    : null, // Disabled until payment verified
                                icon: const Icon(Icons.home),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 48,
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  elevation: 4,
                                ),
                                label: const Text(
                                  'Proceed to Home',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
