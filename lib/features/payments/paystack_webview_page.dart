import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:local_lekker/services/navigation_service.dart';
import 'package:local_lekker/services/subscription_service.dart';
import 'package:local_lekker/services/paystack_service.dart';
import 'package:local_lekker/services/payment_status_service.dart';
import 'package:local_lekker/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:local_lekker/widgets/browser_payment_option.dart';

class PaystackWebViewPage extends StatefulWidget {
  final String authorizationUrl;
  final String userId;
  final String planType;
  final String? transactionReference;
  final Map<String, dynamic>? promoContext;

  const PaystackWebViewPage({
    super.key,
    required this.authorizationUrl,
    required this.userId,
    required this.planType,
    this.transactionReference,
    this.promoContext,
  });

  @override
  State<PaystackWebViewPage> createState() => _PaystackWebViewPageState();
}

class _PaystackWebViewPageState extends State<PaystackWebViewPage> with WidgetsBindingObserver {
  final Logger _logger = Logger();
  final PaystackService _paystackService = PaystackService();
  late final WebViewController _controller;
  bool _loading = true;
  bool _processingPayment = false;
  bool _showingSuccess = false;
  bool _showManualVerify = false;
  bool _checkoutLoaded = false;
  bool _awaitingExternalAuth = false;
  bool _paymentDeclined = false; // Paystack showed an "unable to process" / risk-block page
  bool _paymentHandled = false; // Once true, no detection mechanism can re-trigger
  String _processingStatus = 'Processing payment...';
  bool _pollingActive = false; // Prevent multiple concurrent polling timers
  Timer? _successCheckTimer;
  Timer? _manualVerifyTimer;
  Timer? _apiVerifyTimer; // Direct Paystack API polling (most reliable)
  RealtimeChannel? _subscriptionChannel;

  String get _callbackUrl {
    // Prefer explicit callback URL if provided, else use app scheme
    final webCallbackUrl = dotenv.env['PAYSTACK_CALLBACK_URL'];
    return webCallbackUrl ?? 'locallekker://payment/callback';
  }

  bool _isPaystackSuccessUrl(String url) {
    // Check for explicit Paystack success indicators
    final isPaystackUrl =
        url.contains('checkout.paystack.com') || url.contains('paystack.com');
    // IMPORTANT: Do NOT treat trxref= or reference= as success indicators.
    // Paystack includes these in ALL redirect URLs regardless of outcome.
    final hasSuccessIndicator =
        url.contains('status=success') ||
        url.contains('payment-successful') ||
        url.contains('transaction-successful');

    _logger.d(
      'Checking URL - isPaystackUrl: $isPaystackUrl, hasSuccessIndicator: $hasSuccessIndicator',
    );
    return isPaystackUrl && hasSuccessIndicator;
  }

  /// Check if URL is a redirect with reference params (does NOT mean success)
  bool _isPaystackRedirectUrl(String url) {
    return (url.contains('trxref=') || url.contains('reference='));
  }

  String? _extractReferenceFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      String? reference =
          uri.queryParameters['reference'] ?? uri.queryParameters['trxref'];
      if (reference == null || reference.isEmpty) {
        final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.isNotEmpty) {
          reference = segments.last;
        }
      }
      return (reference != null && reference.isNotEmpty) ? reference : null;
    } catch (e) {
      _logger.w('Failed to parse reference from URL: $e');
      return null;
    }
  }

  /// Phrases Paystack's hosted checkout shows when the bank or Paystack's
  /// risk engine rejects a charge (e.g. the generic "Unable to process
  /// transaction" screen — common after several rapid attempts on the same
  /// customer). Kept specific to avoid false positives on the card form.
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

  /// Surface a clear in-app banner when Paystack declines the charge, so the
  /// member is not left staring at a generic error with no explanation. The
  /// flag is re-evaluated on every poll, so it clears itself the moment the
  /// member navigates back to the card form ("Try another card").
  void _evaluateDeclineText(String bodyText) {
    if (!mounted) return;
    if (_paymentHandled || _showingSuccess || _processingPayment) {
      if (_paymentDeclined) setState(() => _paymentDeclined = false);
      return;
    }
    final looksDeclined = _declineIndicators.any(bodyText.contains);
    if (looksDeclined != _paymentDeclined) {
      if (looksDeclined) {
        _logger.w('Detected Paystack decline/risk page — showing member guidance');
      }
      setState(() => _paymentDeclined = looksDeclined);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App going to background - likely opening banking app for 3DS
      if (_checkoutLoaded && !_processingPayment && !_showingSuccess) {
        _awaitingExternalAuth = true;
        _logger.i('App paused during payment - marking as awaiting external auth');
      }
    } else if (state == AppLifecycleState.resumed && _awaitingExternalAuth) {
      // App resumed from background - likely returning from 3DS banking app
      _awaitingExternalAuth = false;
      _logger.i('App resumed from background - attempting silent payment verification');
      // Brief delay to allow Paystack to settle the transaction
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_processingPayment && !_showingSuccess) {
          _silentVerifyPayment();
        }
      });
    }
  }

  /// Silently check if payment is complete without showing UI.
  /// Only shows processing overlay if verification succeeds.
  /// Restarts polling on failure so auto-detection continues.
  Future<void> _silentVerifyPayment({String? url}) async {
    if (_processingPayment || _showingSuccess || _paymentHandled) return;

    String? ref;
    if (url != null) {
      ref = _extractReferenceFromUrl(url);
    }
    ref ??= widget.transactionReference;

    if (ref == null) return;

    _logger.d('Silent verification check for ref: $ref');

    try {
      final verifiedDetails = await _paystackService.verifyTransaction(ref);
      if (verifiedDetails != null) {
        _logger.i('Silent verification: transaction CONFIRMED successful');
        if (mounted && !_processingPayment && !_showingSuccess) {
          setState(() {
            _processingPayment = true;
            _processingStatus = 'Payment verified! Setting up your account...';
          });
          await _handlePaymentSuccess(url: url);
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

  /// Gateway: verify transaction with Paystack API before handling success.
  Future<void> _verifyAndHandlePayment({String? url}) async {
    if (_processingPayment || _paymentHandled) {
      _logger.w('Payment already being processed or handled, ignoring duplicate');
      return;
    }

    // Stop polling while we verify to prevent concurrent detections
    _successCheckTimer?.cancel();

    // Show processing spinner while verifying
    if (mounted) {
      setState(() {
        _processingPayment = true;
        _showingSuccess = false;
        _processingStatus = 'Verifying your payment...';
      });
    }

    _logger.i('=== VERIFYING SUBSCRIPTION PAYMENT WITH PAYSTACK API ===');

    // Extract reference from URL first, fall back to stored transaction reference
    String? ref;
    if (url != null) {
      ref = _extractReferenceFromUrl(url);
    }
    // Fall back to the stored transaction reference from initialization
    ref ??= widget.transactionReference;

    if (ref == null) {
      _logger.w('No transaction reference found - cannot verify payment');
      if (mounted) {
        setState(() => _processingPayment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment not yet completed. Please complete the payment or try again.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    _logger.i('Verifying transaction reference: $ref');

    // Verify with Paystack API with retries
    // Use more retries with longer delays to handle 3DS bank authentication
    Map<String, dynamic>? verifiedDetails;
    int retryCount = 0;
    const maxRetries = 6;
    const retryDelays = [2, 3, 4, 5, 6, 8]; // seconds between attempts

    while (retryCount < maxRetries) {
      try {
        verifiedDetails = await _paystackService.verifyTransaction(ref);
        if (verifiedDetails != null) {
          _logger.i('Transaction verified as SUCCESS on attempt ${retryCount + 1}');
          break;
        } else {
          _logger.w('Transaction NOT successful on attempt ${retryCount + 1}');
        }
      } catch (e) {
        _logger.w('Verification attempt ${retryCount + 1} failed: $e');
      }

      retryCount++;
      if (retryCount < maxRetries) {
        await Future.delayed(Duration(seconds: retryDelays[retryCount - 1]));
      }
    }

    if (verifiedDetails == null) {
      // Paystack API didn't confirm success — but the webhook may have already
      // activated the subscription in the database. Check directly.
      _logger.i('API verification failed, checking DB for webhook-activated subscription...');
      try {
        final dbCheck = await SupabaseService.instance.client
            .from('subscriptions')
            .select('status')
            .eq('user_id', widget.userId)
            .eq('status', 'active')
            .limit(1);
        if (dbCheck.isNotEmpty) {
          _logger.i('Subscription already active in DB (webhook handled it) — navigating home');
          if (mounted && !_paymentHandled) {
            _paymentHandled = true;
            _successCheckTimer?.cancel();
            _manualVerifyTimer?.cancel();
            _apiVerifyTimer?.cancel();
            _subscriptionChannel?.unsubscribe();
            _subscriptionChannel = null;
            // Clear pending transaction reference
            try {
              await PaymentStatusService().clearPendingTransactionReference(widget.userId);
              await PaymentStatusService().clearPendingPayment(widget.userId);
            } catch (_) {}
            setState(() {
              _showingSuccess = true;
              _processingPayment = true;
            });
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                NavigationService().navigateToHomeAfterPayment(context);
              }
            });
          }
          return;
        }
      } catch (e) {
        _logger.w('DB subscription check failed: $e');
      }

      _logger.e('Payment verification not confirmed after $maxRetries attempts');
      if (mounted) {
        setState(() {
          _processingPayment = false;
          _showManualVerify = true;
        });
        _logger.i('Verification failed — showing manual verify button (no auto-restart)');
      }
      return;
    }

    // Payment verified - proceed
    _logger.i('Payment VERIFIED, proceeding to activate subscription');
    await _handlePaymentSuccess(url: url);
  }

  Future<void> _handlePaymentSuccess({String? url}) async {
    // Prevent re-entry — once payment handling starts, nothing else should trigger it
    if (_paymentHandled) {
      _logger.w('Payment already handled, ignoring duplicate _handlePaymentSuccess call');
      return;
    }
    _paymentHandled = true;

    // Stop ALL detection mechanisms immediately
    _successCheckTimer?.cancel();
    _manualVerifyTimer?.cancel();
    _apiVerifyTimer?.cancel();
    _subscriptionChannel?.unsubscribe();
    _subscriptionChannel = null;

    if (kDebugMode) {
      print('✅ ========================================');
    }
    if (kDebugMode) {
      print('✅ PAYMENT SUCCESS HANDLER CALLED');
    }
    if (kDebugMode) {
      print('✅ UserId: ${widget.userId}');
    }
    if (kDebugMode) {
      print('✅ PlanType: ${widget.planType}');
    }
    if (kDebugMode) {
      print('✅ ========================================');
    }
    _logger.i('=== PAYMENT SUCCESS HANDLER CALLED ===');
    // Clear any lingering error SnackBars before showing success
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }
    // Show spinner overlay while we activate the subscription
    if (mounted) {
      setState(() {
        _processingPayment = true;
        _showingSuccess = false;
        _processingStatus = 'Payment verified! Saving card details...';
      });
    }
    _logger.i('Processing overlay visible with spinner.');
    _logger.i(
      'Processing payment for userId: ${widget.userId}, planType: ${widget.planType}',
    );

    try {
      // Try to verify Paystack transaction and save authorization for renewals
      String? reference;
      if (url != null) {
        reference = _extractReferenceFromUrl(url);
      }
      // Fall back to stored transaction reference
      reference ??= widget.transactionReference;
      _logger.i('Using reference for card save: ${reference ?? 'none'}');
      if (reference != null) {
          try {
            _logger.i('Verifying Paystack transaction: $reference');
            final paymentDetails = await _paystackService.verifyTransaction(
              reference,
            );
            if (paymentDetails != null &&
                paymentDetails['authorization'] != null) {
              final auth = paymentDetails['authorization'];
              final authorizationCode = auth['authorization_code'];
              if (authorizationCode != null &&
                  authorizationCode.toString().isNotEmpty &&
                  auth['reusable'] == true) {
                final existing = await _paystackService.getSavedPaymentMethods(
                  widget.userId,
                );
                final shouldSetPrimary =
                    existing.isEmpty ||
                    !existing.any((m) => m['is_primary'] == true);

                final cardDetails = {
                  'card_type': auth['card_type'] ?? 'card',
                  'last4': auth['last4'] ?? '****',
                  'exp_month': auth['exp_month'],
                  'exp_year': auth['exp_year'],
                  'bank': auth['bank'],
                  'brand': auth['brand'],
                  'is_primary': shouldSetPrimary,
                };

                _logger.i(
                  'Saving authorization_code for user ${widget.userId}: $authorizationCode',
                );
                try {
                  await _paystackService.addPaymentMethod(
                    widget.userId,
                    authorizationCode,
                    cardDetails,
                  );
                  if (shouldSetPrimary) {
                    await _paystackService.setPrimaryPaymentMethod(
                      widget.userId,
                      authorizationCode,
                    );
                  }
                } catch (e) {
                  _logger.w(
                    'addPaymentMethod failed (possibly duplicate). Continuing. Error: $e',
                  );
                }
              } else {
                _logger.w('No reusable authorization found; payment will not save a renewal card');
              }

              // Save customer_code to profile so subsequent checkouts
              // surface saved card with CVV-only prompt
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
                  _logger.w('Failed saving customer_code: $e');
                }
              }
            } else {
              _logger.w('Payment verification returned no authorization data');
            }
          } catch (e) {
            _logger.w('Failed to verify transaction or save card: $e');
          }
        }

      // Update status before activating subscription
      if (mounted) {
        setState(() => _processingStatus = 'Activating your subscription...');
      }

      // Retrieve Paystack subscription code for auto-renewal webhook matching.
      // When a transaction is initialized with a plan code, Paystack creates a
      // subscription (SUB_xxx) automatically. We need to save this code so that
      // future webhook events (subscription.charge, invoice.payment_failed,
      // subscription.disable) can be matched to the correct user.
      String? paystackSubscriptionCode;
      try {
        final customerCode = await _paystackService.getPaystackCustomerCode(widget.userId);
        if (customerCode != null && customerCode.isNotEmpty) {
          paystackSubscriptionCode = await _paystackService.getCustomerSubscriptionCode(
            customerCodeOrEmail: customerCode,
          );
          if (paystackSubscriptionCode != null) {
            _logger.i('Retrieved Paystack subscription code: $paystackSubscriptionCode');
          }
        }
      } catch (e) {
        _logger.w('Could not retrieve Paystack subscription code: $e');
      }

      bool success;
      if (widget.planType == 'promotion_intro') {
        final promo = widget.promoContext;
        if (promo == null) {
          throw Exception('Missing promo context for intro payment activation');
        }

        _logger.i('Calling SubscriptionService.activateIntroCampaignSubscription...');
        success = await SubscriptionService().activateIntroCampaignSubscription(
          userId: widget.userId,
          promotionId: promo['promotion_id'] as String,
          participantId: promo['participant_id'] as String,
          freeMonths: (promo['free_months'] as int?) ?? 0,
          initialChargeCents: (promo['initial_charge_cents'] as int?) ?? 100,
          renewalChargeCents: (promo['renewal_charge_cents'] as int?) ?? 9900,
          introChargeReference: reference,
        );
      } else {
        // Mark subscription active and start new billing period
        _logger.i('Calling SubscriptionService.processManualPayment...');
        success = await SubscriptionService().processManualPayment(
          userId: widget.userId,
          planType: widget.planType,
          paystackSubscriptionCode: paystackSubscriptionCode,
        );
      }

      _logger.i('processManualPayment returned: $success');

      if (!success) {
        throw Exception('processManualPayment returned false');
      }

      _logger.i('Subscription activated successfully');

      // Clear pending transaction reference since payment was processed
      try {
        await PaymentStatusService().clearPendingTransactionReference(widget.userId);
        await PaymentStatusService().clearPendingPayment(widget.userId);
      } catch (e) {
        _logger.w('Failed to clear pending transaction reference: $e');
      }

      // Show success screen with "Proceed to Home Page" button
      if (mounted) {
        _logger.i('Showing success screen with proceed button');
        setState(() {
          _showingSuccess = true;
          _processingPayment = true; // Keep overlay visible with success UI
        });
        // Auto-navigate home after 5 seconds if user doesn't tap the button
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && _showingSuccess) {
            _logger.i('Auto-navigating to home after 5s on success screen');
            NavigationService().navigateToHomeAfterPayment(context);
          }
        });
      } else {
        _logger.e('Widget is not mounted after processManualPayment');
      }
    } catch (e, stackTrace) {
      _logger.e('Error processing payment: $e');
      _logger.e('Stack trace: $stackTrace');
      if (mounted) {
        // Payment was taken — show success and navigate home.
        // The recovery flow in NavigationService will activate the subscription on next launch.
        setState(() {
          _showingSuccess = true;
          _processingPayment = true;
          _processingStatus = 'Payment received! Setting up your account...';
        });
        // Navigate home after a short delay so recovery can finish activation
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            NavigationService().navigateToHomeAfterPayment(context);
          }
        });
      }
    }
  }

  /// Periodically verify the transaction reference directly with Paystack API.
  /// This bypasses all WebView content/URL detection and is the most reliable
  /// mechanism for detecting payment completion.
  void _startApiVerificationPolling() {
    final ref = widget.transactionReference;
    if (ref == null || ref.isEmpty) {
      _logger.w('No transaction reference for API polling');
      return;
    }

    // Wait 10 seconds before first check (give user time to enter card details)
    Future.delayed(const Duration(seconds: 10), () {
      if (!mounted || _paymentHandled || _processingPayment || _showingSuccess) return;

      int apiPollCount = 0;
      const maxApiPolls = 60; // 60 × 5s = 300 seconds total coverage

      _apiVerifyTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        apiPollCount++;
        if (_paymentHandled || _processingPayment || _showingSuccess) {
          timer.cancel();
          return;
        }

        _logger.d('API verify poll #$apiPollCount/$maxApiPolls for ref: $ref');

        try {
          final result = await _paystackService.verifyTransaction(ref);
          if (result != null && !_paymentHandled && !_processingPayment) {
            _logger.i('API polling: transaction CONFIRMED successful on attempt $apiPollCount');
            timer.cancel();
            if (mounted) {
              setState(() {
                _processingPayment = true;
                _processingStatus = 'Payment verified! Setting up your account...';
              });
              await _handlePaymentSuccess();
            }
          }
        } catch (e) {
          _logger.d('API verify poll #$apiPollCount failed: $e');
        }

        if (apiPollCount >= maxApiPolls) {
          timer.cancel();
          _logger.w('API verification polling timed out after ${maxApiPolls * 5}s');
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
    _subscriptionChannel?.unsubscribe();
    super.dispose();
  }

  /// Listen for subscription activation via Supabase Realtime.
  /// When the Paystack webhook processes the payment server-side, it sets
  /// subscriptions.status = 'active'. This listener catches that change and
  /// navigates the member home immediately — bypassing the webview polling.
  void _setupRealtimeSubscriptionListener() {
    try {
      _subscriptionChannel = SupabaseService.instance.client
          .channel('subscription_payment_${widget.userId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'subscriptions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: widget.userId,
            ),
            callback: (payload) {
              _logger.i('Realtime: subscription INSERT detected');
              final newRecord = payload.newRecord;
              if (newRecord['status'] == 'active') {
                _onRealtimeSubscriptionActivated();
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'subscriptions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: widget.userId,
            ),
            callback: (payload) {
              _logger.i('Realtime: subscription UPDATE detected');
              final newRecord = payload.newRecord;
              if (newRecord['status'] == 'active') {
                _onRealtimeSubscriptionActivated();
              }
            },
          )
          .subscribe();

      _logger.i('Realtime subscription listener active for user ${widget.userId}');
    } catch (e) {
      _logger.w('Failed to set up realtime subscription listener: $e');
    }
  }

  /// Called when Supabase Realtime detects the subscription is now active.
  void _onRealtimeSubscriptionActivated() {
    if (!mounted || _showingSuccess || _paymentHandled) return;

    _logger.i('Realtime detected subscription activation — navigating home');

    _paymentHandled = true;

    // Stop all polling/timers
    _successCheckTimer?.cancel();
    _manualVerifyTimer?.cancel();
    _apiVerifyTimer?.cancel();

    setState(() {
      _processingPayment = true;
      _showingSuccess = true;
    });

    // Brief delay so the user sees the success screen
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        NavigationService().navigateToHomeAfterPayment(context);
      }
    });
  }

  void _startSuccessPolling() {
    // Prevent multiple concurrent polling timers
    if (_pollingActive || _paymentHandled || _processingPayment || _showingSuccess) {
      _logger.d('Skipping polling start — already active or payment handled');
      return;
    }
    _successCheckTimer?.cancel();
    _pollingActive = true;
    int pollCount = 0;
    const maxPolls = 30; // Poll for 150 seconds (30 x 5s)

    _successCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      pollCount++;
      _logger.d('Subscription polling for payment completion... attempt $pollCount/$maxPolls');

      if (_processingPayment || _showingSuccess || _paymentHandled) {
        timer.cancel();
        _pollingActive = false;
        return;
      }

      try {
        final currentUrl = await _controller.currentUrl();

        // If URL has explicit success status indicator, verify via API
        if (currentUrl != null && _isPaystackSuccessUrl(currentUrl)) {
          _logger.i('Polling detected success URL: $currentUrl');
          timer.cancel();
          _pollingActive = false;
          await _verifyAndHandlePayment(url: currentUrl);
          return;
        }

        // If URL is a redirect with reference AND matches our callback URL,
        // verify via Paystack API. We require callback URL match to avoid
        // premature verification during 3DS redirect chains where bank URLs
        // may also contain reference parameters.
        if (currentUrl != null &&
            _isPaystackRedirectUrl(currentUrl) &&
            currentUrl.startsWith(_callbackUrl)) {
          _logger.i('Polling detected callback redirect URL with reference: $currentUrl');
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
          _logger.d('Polling detected non-callback redirect with reference - silent check');
          await _silentVerifyPayment(url: currentUrl);
          // Don't cancel timer - let polling continue if silent check fails
          if (_processingPayment || _showingSuccess) {
            timer.cancel();
            _pollingActive = false;
            return;
          }
        }

        // Check page text for definitive success messages
        final bodyTextResult = await _controller.runJavaScriptReturningResult(
          'document.body.innerText.toLowerCase()',
        );
        // Strip surrounding quotes - runJavaScriptReturningResult returns
        // a JSON-encoded string (e.g. '"some text"'), so we trim quotes.
        final bodyText = bodyTextResult.toString().toLowerCase()
            .replaceAll(RegExp(r'^["\s]+|["\s]+$'), '');

        if (bodyText.contains('you paid') ||
            bodyText.contains('payment successful')) {
          _logger.i('Polling detected definitive success text in page');
          timer.cancel();
          _pollingActive = false;
          await _verifyAndHandlePayment(url: currentUrl);
          return;
        }

        // Detect a decline/risk-block state (Paystack checkout is an SPA, so
        // this renders without a page reload — polling is the reliable catch).
        _evaluateDeclineText(bodyText);
      } catch (e) {
        _logger.w('Subscription polling error: $e');
      }

      if (pollCount >= maxPolls) {
        _logger.w('Subscription polling timed out after ${maxPolls * 5} seconds');
        timer.cancel();
        _pollingActive = false;

        // Show the manual verify button instead of auto-triggering
        // verification. The user may still be entering card details;
        // auto-verifying would show a false "Payment was not completed" error.
        if (mounted && !_processingPayment && !_showingSuccess) {
          setState(() => _showManualVerify = true);
          _logger.i('Polling timeout - showing manual verify button');
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Listen for webhook-driven subscription activation via Supabase Realtime.
    // The Paystack webhook independently activates the subscription in the DB,
    // so this fires even when the webview API verification loop is stuck.
    _setupRealtimeSubscriptionListener();

    // Start direct API verification polling after 15 seconds.
    // This is the most reliable detection: it asks Paystack directly
    // "is this transaction done?" without relying on WebView content.
    _startApiVerificationPolling();

    // Show manual verify fallback after 45 seconds in case auto-detection fails
    _manualVerifyTimer = Timer(const Duration(seconds: 45), () {
      if (mounted && !_processingPayment && !_showingSuccess) {
        setState(() => _showManualVerify = true);
        _logger.i('Manual verify fallback now visible (45s elapsed)');
      }
    });

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
            if (kDebugMode) {
              print('🌐 WebView Page Started: $url');
            }
          },
          onPageFinished: (url) async {
            setState(() => _loading = false);
            if (kDebugMode) {
              print('🌐 ========================================');
              print('🌐 PAGE FINISHED LOADING');
              print('🌐 URL: $url');
            }
            _logger.i('=== PAGE FINISHED LOADING ===');
            _logger.i('URL: $url');

            // Track whether we're on a Paystack-related page
            // Include both .com and .co domains (API uses paystack.co)
            final isPaystackPage =
                url.contains('paystack.com') ||
                url.contains('paystack.co');

            // Mark checkout as loaded once we've reached a Paystack page
            if (isPaystackPage && !_checkoutLoaded) {
              _checkoutLoaded = true;
              _logger.i('Checkout page loaded successfully');
            }

            // Check if page is blank (custom scheme redirect aftermath)
            // Guards:
            // 1. Skip non-HTTP URLs (about:blank, data:, custom schemes)
            // 2. Skip any Paystack domain (SPA may show blank briefly)
            // 3. Only check AFTER checkout has loaded at least once
            // 4. Only auto-verify AFTER manual verify timer (45s) to avoid
            //    premature verification during 3DS redirect chains
            if (url.startsWith('http') &&
                !isPaystackPage &&
                _checkoutLoaded &&
                _showManualVerify) {
              try {
                final pageContent = await _controller
                    .runJavaScriptReturningResult('document.body.innerText.trim()');
                final content = pageContent.toString().toLowerCase();
                if (content.length < 50 && !_processingPayment && !_showingSuccess) {
                  _logger.w('Detected potentially blank/stuck page at non-Paystack URL: $url');
                  // If we have a stored reference and page is blank, try silent verification
                  if (widget.transactionReference != null) {
                    _logger.i('Blank page with stored reference - attempting silent verification');
                    _silentVerifyPayment(url: url);
                    return;
                  }
                }
              } catch (e) {
                _logger.w('Could not check page content: $e');
              }
            }

            // Check if this is an explicit success URL - verify via API
            if (_isPaystackSuccessUrl(url) && !_paymentHandled) {
              _logger.i('Detected Paystack success URL, verifying: $url');
              _verifyAndHandlePayment(url: url);
              return;
            }

            // Check if URL is a redirect with reference (callback)
            // Must verify via API - do NOT assume success
            if (_isPaystackRedirectUrl(url) && url.startsWith(_callbackUrl)) {
              _logger.i('Detected callback redirect, verifying: $url');
              _verifyAndHandlePayment(url: url);
              return;
            }

            // Check page text for definitive Paystack success messages
            if (isPaystackPage) {
              try {
                final bodyTextResult = await _controller
                    .runJavaScriptReturningResult('document.body.innerText.toLowerCase()');
                // Strip surrounding quotes from JS result
                final bodyText = bodyTextResult.toString().toLowerCase()
                    .replaceAll(RegExp(r'^["\s]+|["\s]+$'), '');

                if (bodyText.contains('you paid') ||
                    bodyText.contains('payment successful')) {
                  if (!_paymentHandled) {
                    _logger.i('Detected definitive success text, verifying via API');
                    _verifyAndHandlePayment(url: url);
                    return;
                  }
                }

                // Detect a decline/risk-block state on the loaded page.
                _evaluateDeclineText(bodyText);
              } catch (e) {
                _logger.w('Could not check page content: $e');
              }
            }

            _logger.d('No success indicators detected on this page');

            // Override window.open() to redirect 3DS popup navigation into
            // this WebView window. Paystack's hosted checkout opens the bank
            // authorization page via window.open(); webview_flutter blocks
            // popups by default, so without this override Paystack detects
            // the failed popup and navigates to its /close URL which
            // dismisses the WebView before the bank auth page is shown.
            if (isPaystackPage) {
              try {
                await _controller.runJavaScript(r'''
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
                _logger.d('Injected window.open override for 3DS popup handling (channel-based)');
              } catch (e) {
                _logger.w('Could not inject window.open override: $e');
              }
            }

            // Start polling on Paystack pages to detect success.
            // Delay polling start to avoid interfering with card entry,
            // OTP/PIN verification, and 3DS redirect flows.
            if (isPaystackPage && !_processingPayment && !_showingSuccess && !_paymentHandled && !_pollingActive) {
              _logger.i('On Paystack page - will start completion polling after delay');
              Future.delayed(const Duration(seconds: 10), () {
                if (mounted && !_processingPayment && !_showingSuccess && !_paymentHandled) {
                  _startSuccessPolling();
                }
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            _logger.d('Navigation request: $url');

            // Detect callback URL - verify via API before treating as success
            if (url.startsWith(_callbackUrl)) {
              _logger.i('Detected callback URL, verifying: $url');
              _verifyAndHandlePayment(url: url);
              return NavigationDecision.prevent;
            }

            // Detect Paystack-specific close/cancel URLs only.
            // IMPORTANT: Only match Paystack domains to avoid blocking
            // 3DS bank redirect URLs that may contain '/close' in their path.
            // If the close URL includes a transaction reference the payment
            // may have completed — verify via API before dismissing.
            final isPaystackDomain = url.contains('paystack.com') || url.contains('paystack.co');
            if (isPaystackDomain && (url.endsWith('/close') || url.endsWith('/cancel') ||
                url.contains('/close?') || url.contains('/cancel?'))) {
              _logger.w('Detected Paystack close/cancel URL: $url');
              final hasReference = url.contains('trxref=') || url.contains('reference=');
              if (hasReference) {
                _logger.i('Close URL has reference params — verifying before dismissing');
                _verifyAndHandlePayment(url: url);
              } else if (mounted) {
                // Delay pop to allow the webhook / realtime listener to activate
                // the subscription if 3DS completed just before the /close fired.
                // If verification confirms success it takes over; otherwise pop.
                _logger.i('Close URL without reference — waiting 4s before verifying/pop');
                Future.delayed(const Duration(seconds: 4), () {
                  if (!mounted || _paymentHandled || _showingSuccess) return;
                  _silentVerifyPayment();
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted && !_paymentHandled && !_showingSuccess) {
                      Navigator.of(context).pop();
                    }
                  });
                });
              }
              return NavigationDecision.prevent;
            }

            // Detect explicit success URL - verify via API
            if (_isPaystackSuccessUrl(url)) {
              _logger.i('Detected success URL, verifying: $url');
              _verifyAndHandlePayment(url: url);
              return NavigationDecision.prevent;
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
          if (_paymentHandled || _processingPayment || _showingSuccess) return;
          if (!url.startsWith('http')) return;
          if (url.contains('/cookie-support/')) return;
          _logger.i('PaystackPopup channel: loading 3DS auth URL: $url');
          _controller.loadRequest(Uri.parse(url));
        },
      );

    // Paystack 3DS relies on third-party cookies, which Android WebView blocks by default.
    final platformController = _controller.platform;
    if (platformController is AndroidWebViewController) {
      AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ).setAcceptThirdPartyCookies(platformController, true);
    }

    _controller.loadRequest(Uri.parse(widget.authorizationUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_processingPayment && !_showingSuccess,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_showingSuccess) {
          // Payment was successful - navigate home instead of going back
          _logger.i('Back button pressed on success screen - navigating home');
          await NavigationService().navigateToHomeAfterPayment(context);
        }
      },
      child: Scaffold(
      appBar: BrandedAppBar(
        title: Text(_showingSuccess ? 'Payment Complete' : 'Secure Payment'),
        leading: _showingSuccess
            ? IconButton(
                icon: const Icon(Icons.home),
                onPressed: () async {
                  _logger.i('Home button pressed on success screen');
                  await NavigationService().navigateToHomeAfterPayment(context);
                },
              )
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
      ),
      body: Column(
        children: [
          if (isGooglePayBrowserCheckoutEnabled &&
              !_processingPayment &&
              !_showingSuccess)
            BrowserPaymentOption(authorizationUrl: widget.authorizationUrl),
          Expanded(child: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading && !_processingPayment)
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          if (_paymentDeclined && !_processingPayment && !_showingSuccess)
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
                          Icon(Icons.info_outline, color: Colors.red.shade700),
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
                        style: TextStyle(color: Colors.red.shade800, fontSize: 13),
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
          if (_processingPayment)
            Container(
              color: Colors.white,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    );
                  },
                  child: _showingSuccess
                      ? Column(
                          key: const ValueKey('success'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Your subscription has been activated.',
                              style: TextStyle(fontSize: 16, color: Colors.black54),
                            ),
                            const SizedBox(height: 32),
                            ElevatedButton.icon(
                              onPressed: () async {
                                _logger.i('Proceed to home page button pressed');
                                setState(() => _processingPayment = false);
                                await NavigationService().navigateToHomeAfterPayment(
                                  context,
                                );
                              },
                              icon: const Icon(Icons.arrow_forward, color: Colors.white),
                              label: const Text(
                                'Proceed to Home Page',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 48,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          key: const ValueKey('loading'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 24),
                            SizedBox(
                              width: 60,
                              height: 60,
                              child: CircularProgressIndicator(
                                strokeWidth: 4,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade600),
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              _processingStatus,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Please wait, do not close this screen.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          // Subtle fallback button - only appears after 45 seconds if auto-detection hasn't triggered
          if (!_showingSuccess && !_processingPayment && _showManualVerify)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: TextButton.icon(
                  onPressed: () {
                    if (kDebugMode) {
                      print('🔘 MANUAL VERIFY BUTTON PRESSED');
                    }
                    _pollingActive = false; // Allow fresh verification
                    _verifyAndHandlePayment();
                  },
                  icon: const Icon(Icons.help_outline, size: 18, color: Colors.grey),
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
        ],
      )),
        ],
      ),
    ),
    );
  }
}
