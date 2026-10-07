import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:local_lekker/services/web_checkout.dart';

/// Thrown when a member tries to save more than [PaystackService.maxSavedCards]
/// cards. The UI catches this to prompt the member to delete an existing card
/// before adding a new one.
class CardLimitException implements Exception {
  CardLimitException(this.maxCards);

  final int maxCards;

  @override
  String toString() =>
      'You can only save up to $maxCards cards. Delete a card to add a new one.';
}

class PaystackService {
  final Logger _logger = Logger();

  /// Maximum number of active saved cards a member can keep on file at once
  /// (the original signup card plus two additional cards). To add another card
  /// beyond this limit the member must first delete an existing one.
  static const int maxSavedCards = 3;

  String? get _paystackLogoUrl {
    final raw = dotenv.env['PAYSTACK_LOGO_URL']?.trim();
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }

    // For Flutter web local testing, fall back to a tighter brand asset that
    // Paystack can fetch from the same local dev server. This makes the hosted
    // card-details page materially more visible than the padded wordmark.
    if (kIsWeb && (Uri.base.scheme == 'http' || Uri.base.scheme == 'https')) {
      return Uri.base.resolve('assets/heart_flag.png').toString();
    }

    return null;
  }

  Map<String, dynamic> _buildCheckoutCustomizations({
    required String title,
    required String description,
  }) {
    final customizations = <String, dynamic>{
      'title': title,
      'description': description,
    };

    final logoUrl = _paystackLogoUrl;
    if (logoUrl != null) {
      customizations['logo'] = logoUrl;
    }

    return customizations;
  }

  // ── Server-side proxy ──────────────────────────────────────────────
  // All Paystack secret-key calls are routed through the paystack-proxy
  // Edge Function so the secret key never ships in the APK.
  //
  // The Edge Function authenticates via Supabase JWT and forwards the
  // request to https://api.paystack.co with the secret key attached
  // server-side.
  // ────────────────────────────────────────────────────────────────────

  /// Send a request to the Paystack API via the paystack-proxy Edge Function.
  /// Returns an [http.Response] whose status code and body match the
  /// upstream Paystack response, so callers can keep existing status-code
  /// checks unchanged.
  ///
  /// Retries up to [maxRetries] times on network errors (connection abort,
  /// timeout, socket exceptions) with exponential back-off. This handles
  /// Edge Function cold-starts and transient mobile network issues.
  Future<http.Response> _proxyRequest({
    required String path,
    String method = 'GET',
    Map<String, dynamic>? body,
    int maxRetries = 1,
    Duration requestTimeout = const Duration(seconds: 15),
  }) async {
    final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final auth = Supabase.instance.client.auth;
    Session? session = auth.currentSession;

    // Refresh the token if it is missing, already expired, or within
    // 60s of expiring — otherwise the Edge Function's local JWT verify
    // will reject it with 401 "Invalid or expired token".
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiresAt = session?.expiresAt ?? 0;
    final needsRefresh = session == null || expiresAt - nowSec < 60;
    if (needsRefresh) {
      try {
        _logger.i('PaystackService: Refreshing expired/near-expired session');
        final refreshed = await auth.refreshSession().timeout(
          const Duration(seconds: 8),
        );
        session = refreshed.session ?? auth.currentSession;
      } catch (e) {
        _logger.w('PaystackService: Session refresh failed: $e');
      }
    }

    final accessToken = session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      _logger.e('PaystackService: No valid session token for proxy request to $path');
      // Return a synthetic 401 response so callers handle it gracefully
      return http.Response(
        jsonEncode({'error': 'Not authenticated. Please sign in again.'}),
        401,
      );
    }

    final url = Uri.parse('$supabaseUrl/functions/v1/paystack-proxy');
    final headers = {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
      'apikey': dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    };
    final requestBody = jsonEncode({
      'path': path,
      'method': method,
      if (body != null) 'body': body,
    });

    bool retriedAfter401 = false;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await http.post(
          url,
          headers: headers,
          body: requestBody,
        ).timeout(requestTimeout);

        // If the proxy still says "Invalid or expired token", force a
        // refresh and retry once — covers the edge case where the local
        // clock skew differs from the Edge Function's server clock.
        if (response.statusCode == 401 && !retriedAfter401) {
          retriedAfter401 = true;
          _logger.w('PaystackService: Got 401 from proxy, forcing session refresh and retrying');
          try {
            final refreshed = await auth.refreshSession().timeout(
              const Duration(seconds: 8),
            );
            final newToken = (refreshed.session ?? auth.currentSession)?.accessToken;
            if (newToken != null && newToken.isNotEmpty) {
              headers['Authorization'] = 'Bearer $newToken';
              continue; // retry with fresh token (doesn't consume an attempt)
            }
          } catch (e) {
            _logger.e('PaystackService: Forced refresh after 401 failed: $e');
          }
        }

        if (response.statusCode >= 400) {
          _logger.e('PaystackService: Proxy $method $path returned ${response.statusCode}: ${response.body}');
        }

        return response;
      } catch (e) {
        _logger.w('PaystackService: Proxy $method $path attempt ${attempt + 1}/${maxRetries + 1} failed: $e');
        if (attempt < maxRetries) {
          // Wait before retrying (2s, then 4s)
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        } else {
          // All retries exhausted — return a synthetic error response
          _logger.e('PaystackService: Proxy $method $path failed after ${maxRetries + 1} attempts');
          return http.Response(
            jsonEncode({'error': 'Connection failed. Please check your internet and try again.'}),
            503,
          );
        }
      }
    }

    // Should not be reached, but satisfy the compiler
    return http.Response(jsonEncode({'error': 'Unexpected error'}), 500);
  }

  /// Run a health check on the paystack-proxy Edge Function.
  /// Returns diagnostic info about whether PAYSTACK_SECRET_KEY is correctly
  /// configured server-side. Useful for debugging "Invalid key" errors.
  Future<Map<String, dynamic>> runHealthCheck() async {
    try {
      final response = await _proxyRequest(
        path: '/__health',
        method: 'POST',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _logger.i('PaystackService HealthCheck: $data');
        return data;
      } else {
        _logger.e('PaystackService HealthCheck failed: ${response.statusCode} ${response.body}');
        return {
          'status': 'error',
          'http_status': response.statusCode,
          'message': response.body,
        };
      }
    } catch (e) {
      _logger.e('PaystackService HealthCheck error: $e');
      return {
        'status': 'error',
        'message': e.toString(),
      };
    }
  }

  // Development mode flag
  bool get _isDevelopmentMode {
    try {
      return dotenv.env['PAYSTACK_DEVELOPMENT_MODE'] == 'true';
    } catch (e) {
      _logger.w(
        'PaystackService: Could not load PAYSTACK_DEVELOPMENT_MODE from env, defaulting to false: $e',
      );
      return false; // Default to production mode
    }
  }

  // Create one-time payment
  /// Starts a one-time Paystack payment and returns a map with
  /// `authorization_url` and `reference` keys, or null on failure.
  Future<Map<String, String>?> startOneTimePayment({
    required String itemName,
    required String itemDescription,
    required double amount,
    required String userId,
    required String userEmail,
    String? subaccountCode, // Optional subaccount for split payments
    String? businessName, // Optional - used for Paystack customizations
    Map<String, dynamic>? extraMetadata, // Extra metadata (e.g. deal_authorization_id)
    bool useCustomerCode =
        true, // When false, do not attach Paystack customer_code so the
              // hosted checkout shows the new-card entry form instead of
              // defaulting to the member's saved card.
  }) async {
    // In development mode, simulate successful payment without Paystack redirect
    if (_isDevelopmentMode) {
      _logger.i(
        'PaystackService: Development mode - Simulating successful one-time payment',
      );
      // Simulate payment processing delay
      await Future.delayed(const Duration(seconds: 2));
      return {
        'authorization_url': 'https://example.com/payment/success',
        'reference': 'dev_${DateTime.now().millisecondsSinceEpoch}',
      };
    }

    try {
      // Build payment data
      // Use app-configured callback URL so our WebView can detect success reliably
      final callbackUrl = paystackCallbackUrl();

      // If we have a Paystack customer_code saved for this user, include it
      // so Paystack shows the saved card and only requires CVV. Skipped when
      // useCustomerCode == false (member explicitly wants to enter a new card).
      String? customerCode;
      if (useCustomerCode) {
        customerCode = await getPaystackCustomerCode(userId);
        customerCode ??= await _ensurePaystackCustomer(
          userId: userId,
          email: userEmail,
        );
      } else {
        _logger.i(
          'PaystackService: Skipping customer_code attachment (new card flow)',
        );
      }

      final String transactionReference =
          'one_time_${userId}_${DateTime.now().millisecondsSinceEpoch}';

      final Map<String, dynamic> paymentData = {
        'email': userEmail,
        'amount': (amount * 100)
            .round(), // Convert to kobo (smallest currency unit)
        'reference': transactionReference,
        'callback_url': callbackUrl,
        'currency': 'ZAR',
        'channels': ['card'],
        'metadata': {
          'user_id': userId,
          'payment_type': 'one_time_payment',
          'item_name': itemName,
          'item_description': itemDescription,
          if (extraMetadata != null) ...extraMetadata,
        },
      };

      // Attach Paystack customer to surface saved cards UI
      if (customerCode != null && customerCode.isNotEmpty) {
        paymentData['customer'] = customerCode;
        _logger.i(
          'PaystackService: Including customer code for saved card CVV-only flow: $customerCode',
        );
      }

      // Add subaccount for DIRECT settlement to partner if provided
      if (subaccountCode != null && subaccountCode.isNotEmpty) {
        paymentData['subaccount'] = subaccountCode;
        // IMPORTANT: Use bearer='account' so Paystack deducts its transaction fee
        // from the Local Lekker main account balance, NOT from the subaccount.
        // bearer='subaccount' caused ZAR transactions to go pending for ~24h then
        // fail because Paystack cannot verify SA bank accounts and the fee
        // deduction from the unverified subaccount triggers a settlement failure.
        paymentData['bearer'] = 'account';
        _logger.i(
          'PaystackService: Including subaccount in payment: $subaccountCode',
        );
        if (kDebugMode) {
          print('✅ SUBACCOUNT INCLUDED: $subaccountCode (bearer=account)');
        }
      } else {
        _logger.w(
          '⚠️ PaystackService: NO subaccount provided - payment will route to platform account',
        );
        if (kDebugMode) {
          print('⚠️ NO SUBACCOUNT - Payment routing to platform account!');
        }
      }

      // Keep the hosted checkout brand-forward so the Local Lekker logo has
      // maximum visibility on Paystack's page.
      paymentData['customizations'] = _buildCheckoutCustomizations(
        title: 'Local Lekker',
        description: businessName != null && businessName.isNotEmpty
            ? '$itemName via $businessName'
            : itemName,
      );

      // Log full payload for debugging
      if (kDebugMode) {
        print('🔍 PAYSTACK INIT PAYLOAD: ${jsonEncode(paymentData)}');
      }
      _logger.i('🔍 Full payment data: $paymentData');

      // Initialize transaction via server-side proxy.
      // Use a 10s per-attempt timeout so two attempts + delay (10+2+10=22s)
      // complete well within the 35s outer timeout applied by the caller.
      final initResponse = await _proxyRequest(
        path: '/transaction/initialize',
        method: 'POST',
        body: paymentData,
        requestTimeout: const Duration(seconds: 10),
      );

      if (initResponse.statusCode == 200) {
        final responseData = jsonDecode(initResponse.body);
        final authorizationUrl = responseData['data']['authorization_url'] as String;

        _logger.i('PaystackService: Payment initialized successfully');
        _logger.i('PaystackService: Transaction reference: $transactionReference');
        if (kDebugMode) {
          print(
            '✅ Paystack transaction initialized - Auth URL: $authorizationUrl',
          );
          print('✅ Transaction reference: $transactionReference');
        }
        return {
          'authorization_url': authorizationUrl,
          'reference': transactionReference,
        };
      } else {
        _logger.e(
          '❌ Paystack init failed: Status ${initResponse.statusCode}, Body: ${initResponse.body}',
        );
        if (kDebugMode) {
          print(
            '❌ PAYSTACK INIT FAILED: ${initResponse.statusCode} - ${initResponse.body}',
          );
        }
        // Check for invalid key specifically
        try {
          final errorData = jsonDecode(initResponse.body);
          final errorCode = errorData['code'] ?? '';
          final errorMsg = errorData['message'] ?? '';
          if (errorCode == 'invalid_Key' || errorMsg.toString().contains('Invalid key')) {
            throw Exception(
              'Payment service configuration error. Please contact support. '
              '(Ref: invalid_api_key)',
            );
          }
        } catch (e) {
          if (e.toString().contains('invalid_api_key')) rethrow;
        }

        String? parsedMessage;
        try {
          final errorData = jsonDecode(initResponse.body);
          parsedMessage =
              (errorData['message'] ?? errorData['error'] ?? '').toString();
        } catch (_) {
          parsedMessage = null;
        }

        final isNetworkFailure = initResponse.statusCode == 503 &&
            (parsedMessage?.toLowerCase().contains('connection failed') ??
                false);
        final isAuthFailure = initResponse.statusCode == 401;

        if (isNetworkFailure) {
          throw Exception(
            'Failed to initialize Paystack payment: network_error - ${parsedMessage ?? 'Connection failed'}',
          );
        }

        if (isAuthFailure) {
          throw Exception(
            'Failed to initialize Paystack payment: auth_error - ${parsedMessage ?? 'Session expired. Please sign in again.'}',
          );
        }

        throw Exception(
          'Failed to initialize Paystack payment: server_error (${initResponse.statusCode}) - ${parsedMessage?.isNotEmpty == true ? parsedMessage : initResponse.body}',
        );
      }
    } catch (e) {
      _logger.e('PaystackService: Error starting one-time payment: $e');
      // Re-throw without wrapping so the caller sees the underlying
      // status/body instead of "Failed to start payment: Exception: ..."
      rethrow;
    }
  }

  // Create subscription payment
  Future<void> startSubscription({
    required String plan,
    required double amount,
    required int frequency, // in months
    required String userId,
    required String userEmail,
  }) async {
    // In development mode, simulate successful payment without Paystack redirect
    if (_isDevelopmentMode) {
      _logger.i(
        'PaystackService: Development mode - Simulating successful subscription payment',
      );
      // Simulate payment processing delay
      await Future.delayed(const Duration(seconds: 2));
      return; // Return early, payment will be marked as completed by caller
    }

    try {
      // First, create a plan if it doesn't exist
      final planResponse = await _proxyRequest(
        path: '/plan',
        method: 'POST',
        body: {
          'name': 'Local Lekker $plan Subscription',
          'interval': 'monthly',
          'amount': (amount * 100).round(), // Convert to kobo
          'description': '$plan subscription plan',
        },
      );

      String planCode;
      if (planResponse.statusCode == 201) {
        final planData = jsonDecode(planResponse.body);
        planCode = planData['data']['plan_code'];
      } else {
        // Plan might already exist, try to get it
        final getPlansResponse = await _proxyRequest(
          path: '/plan',
        );

        if (getPlansResponse.statusCode == 200) {
          final plansData = jsonDecode(getPlansResponse.body);
          final existingPlan = plansData['data'].firstWhere(
            (p) => p['name'] == 'Local Lekker $plan Subscription',
            orElse: () => null,
          );

          if (existingPlan != null) {
            planCode = existingPlan['plan_code'];
          } else {
            throw Exception('Could not create or find subscription plan');
          }
        } else {
          throw Exception('Failed to get plans: ${getPlansResponse.body}');
        }
      }

      // Initialize subscription
      final subResponse = await _proxyRequest(
        path: '/subscription',
        method: 'POST',
        body: {
          'customer': userEmail,
          'plan': planCode,
          'start_date': DateTime.now().toIso8601String(),
          'channels': ['card'],
        },
      );

      if (subResponse.statusCode == 200) {
        final subData = jsonDecode(subResponse.body);
        final authorizationUrl = subData['data']['authorization_url'];

        if (!await launchUrl(
          Uri.parse(authorizationUrl),
          mode: LaunchMode.externalApplication,
        )) {
          throw Exception('Could not open Paystack subscription URL');
        }
      } else {
        throw Exception(
          'Failed to initialize Paystack subscription: ${subResponse.body}',
        );
      }
    } catch (e) {
      _logger.e('PaystackService: Error starting subscription: $e');
      throw Exception('Failed to start subscription: $e');
    }
  }

  // Verify payment notification (webhook)
  // NOTE: Real webhook signature verification now happens server-side
  // in the paystack-webhook Edge Function using HMAC SHA-512.
  // This client-side method is kept for interface compatibility only.
  bool verifyNotification(Map<String, String> notificationData) {
    final signature = notificationData['x-paystack-signature'];
    if (signature == null) return false;
    // Signature verification is done server-side; here we just check presence
    return signature.isNotEmpty;
  }

  // Get transaction status
  Future<Map<String, dynamic>?> getTransactionStatus(String reference) async {
    try {
      final response = await _proxyRequest(
        path: '/transaction/verify/$reference',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'];
      }
    } catch (e) {
      _logger.e('PaystackService: Error getting transaction status: $e');
    }
    return null;
  }

  /// Find the most recent successful subscription transaction for a user by email.
  /// Used to recover payments that succeeded but were not processed by the app
  /// (e.g. user lost signal before the app could activate the subscription).
  Future<Map<String, dynamic>?> findSuccessfulSubscriptionTransaction(String email) async {
    try {
      _logger.i('PaystackService: Searching for successful transactions for $email');
      final response = await _proxyRequest(
        path: '/transaction?email=${Uri.encodeComponent(email)}&status=success&perPage=5',
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final List<dynamic> transactions = responseData['data'] ?? [];

        if (transactions.isEmpty) {
          _logger.i('PaystackService: No successful transactions found for $email');
          return null;
        }

        // Look for subscription-related transactions (with plan metadata or payment_type)
        for (final tx in transactions) {
          final metadata = tx['metadata'] as Map<String, dynamic>? ?? {};
          final paymentType = metadata['payment_type']?.toString() ?? '';
          final hasPlan = tx['plan'] != null && tx['plan'].toString().isNotEmpty;

          if (paymentType == 'subscription' || hasPlan) {
            _logger.i('PaystackService: Found successful subscription transaction: ${tx['reference']}');
            return tx as Map<String, dynamic>;
          }
        }

        // If no subscription-specific transaction, return the most recent one
        // (likely the subscription payment if user just signed up)
        _logger.i('PaystackService: Returning most recent successful transaction: ${transactions[0]['reference']}');
        return transactions[0] as Map<String, dynamic>;
      } else {
        _logger.w('PaystackService: List transactions failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      _logger.e('PaystackService: Error finding successful transactions: $e');
    }
    return null;
  }

  // ==== Customer Code helpers (store on profile to enable saved-card CVV-only flow) ====

  Future<String?> getPaystackCustomerCode(String userId) async {
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('paystack_customer_code')
          .eq('id', userId)
          .maybeSingle();
      final code = res?['paystack_customer_code'] as String?;
      if (code != null && code.isNotEmpty) {
        _logger.d('PaystackService: Found saved paystack_customer_code');
      }
      return code;
    } catch (e) {
      _logger.w('PaystackService: Could not get paystack_customer_code: $e');
      return null;
    }
  }

  // Ensure a Paystack customer exists with the member's name and return the customer_code
  Future<String?> _ensurePaystackCustomer({
    required String userId,
    required String email,
  }) async {
    try {
      // Return cached code if we already have one
      final existing = await getPaystackCustomerCode(userId);
      if (existing != null && existing.isNotEmpty) return existing;

      // Fetch member name details from profiles
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('name, surname')
          .eq('id', userId)
          .maybeSingle();

      String firstName = '';
      String lastName = '';

      if (profile != null) {
        firstName = (profile['name'] as String?)?.trim() ?? '';
        lastName = (profile['surname'] as String?)?.trim() ?? '';
      }

      // Create or update customer on Paystack (creating with same email updates details)
      final response = await _proxyRequest(
        path: '/customer',
        method: 'POST',
        body: {
          'email': email,
          if (firstName.isNotEmpty) 'first_name': firstName,
          if (lastName.isNotEmpty) 'last_name': lastName,
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final code = data['data']?['customer_code'] as String?;
        if (code != null && code.isNotEmpty) {
          await savePaystackCustomerCode(userId: userId, customerCode: code);
          return code;
        }
      } else {
        _logger.w(
          'PaystackService: Failed to create/update customer: ${response.body}',
        );
      }
    } catch (e) {
      _logger.w('PaystackService: Could not ensure customer: $e');
    }
    return null;
  }

  // Helper to get a displayable member name
  Future<String> _getMemberDisplayName(
    String userId,
    String fallbackEmail,
  ) async {
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('name, surname')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 3));
      if (profile != null) {
        final first = (profile['name'] as String?)?.trim() ?? '';
        final last = (profile['surname'] as String?)?.trim() ?? '';
        final combined = [first, last].where((s) => s.isNotEmpty).join(' ');
        if (combined.isNotEmpty) return combined;
      }
    } catch (_) {}
    return 'Member $fallbackEmail';
  }

  Future<void> savePaystackCustomerCode({
    required String userId,
    required String customerCode,
  }) async {
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({
            'paystack_customer_code': customerCode,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
      _logger.i('PaystackService: Saved paystack_customer_code on profile');
    } catch (e) {
      _logger.w('PaystackService: Failed to save paystack_customer_code: $e');
    }
  }

  // Create transfer recipient for banking details collection
  // businessId can be either a business ID (for trusted partners) or a user ID (for members)
  Future<String?> createTransferRecipient({
    required String businessId,
    required String businessName,
    required String bankCode,
    required String accountNumber,
    required String accountName,
    String accountType = 'savings', // Default to savings
    bool isMember = false, // Flag to indicate if this is for a member
  }) async {
    try {
      final String userId;

      if (isMember) {
        // For members, businessId is actually the userId
        userId = businessId;
      } else {
        // For trusted partners, look up the user_id from the business
        final businessResponse = await Supabase.instance.client
            .from('businesses')
            .select('owner_member_id')
            .eq('id', businessId)
            .single();
        userId = businessResponse['owner_member_id'] as String;
      }

      // Check if there's already an existing recipient for this user
      // For members, check members_bank_accounts; for partners, check trusted_partners
      String? existingRecipientCode;

      if (isMember) {
        final existingAccountResponse = await Supabase.instance.client
            .from('members_bank_accounts')
            .select('paystack_recipient_code')
            .eq('user_id', userId)
            .eq('is_active', true)
            .maybeSingle();
        existingRecipientCode =
            existingAccountResponse?['paystack_recipient_code'];
      } else {
        final existingPartnerResponse = await Supabase.instance.client
            .from('trusted_partners')
            .select('paystack_recipient_code')
            .eq('user_id', userId)
            .maybeSingle();
        existingRecipientCode =
            existingPartnerResponse?['paystack_recipient_code'];
      }

      // If there's an existing recipient, delete it from Paystack first
      if (existingRecipientCode != null && existingRecipientCode.isNotEmpty) {
        _logger.i(
          'PaystackService: Deleting existing recipient before creating new one: $existingRecipientCode',
        );
        await deleteTransferRecipient(existingRecipientCode);
      }

      // Map account type to Paystack format for South Africa
      // Both checking and savings accounts in SA use 'basa' (Bank Account South Africa)
      const paystackAccountType = 'basa';

      final recipientResponse = await _proxyRequest(
        path: '/transferrecipient',
        method: 'POST',
        body: {
          'type': paystackAccountType, // Use the mapped account type
          'name': accountName,
          'account_number': accountNumber,
          'bank_code': bankCode,
          'currency': 'ZAR',
        },
      );

      if (recipientResponse.statusCode == 201) {
        final recipientData = jsonDecode(recipientResponse.body);
        final recipientCode = recipientData['data']['recipient_code'];

        _logger.i(
          'PaystackService: Created transfer recipient: $recipientCode',
        );

        // Save recipient code to trusted_partners table
        await _saveRecipientCodeToPartner(
          businessId,
          recipientCode,
          accountType,
        );

        return recipientCode;
      } else {
        throw Exception(
          'Failed to create transfer recipient: ${recipientResponse.body}',
        );
      }
    } catch (e) {
      _logger.e('PaystackService: Error creating transfer recipient: $e');
      throw Exception('Failed to create transfer recipient: $e');
    }
  }

  // Delete transfer recipient from Paystack
  Future<bool> deleteTransferRecipient(String recipientCode) async {
    try {
      final response = await _proxyRequest(
        path: '/transferrecipient/$recipientCode',
        method: 'DELETE',
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['status'] == true) {
          _logger.i(
            'PaystackService: Deleted transfer recipient: $recipientCode',
          );
          return true;
        }
      }

      _logger.w(
        'PaystackService: Failed to delete transfer recipient: $recipientCode',
      );
      return false;
    } catch (e) {
      _logger.e('PaystackService: Error deleting transfer recipient: $e');
      return false;
    }
  }

  // Get transfer recipient details from Paystack
  Future<Map<String, dynamic>?> getTransferRecipient(
    String recipientCode,
  ) async {
    try {
      final response = await _proxyRequest(
        path: '/transferrecipient/$recipientCode',
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['status'] == true) {
          final recipientData = responseData['data'];
          _logger.i(
            'PaystackService: Retrieved transfer recipient: $recipientCode',
          );
          return recipientData;
        }
      }

      _logger.w(
        'PaystackService: Failed to get transfer recipient: $recipientCode',
      );
      return null;
    } catch (e) {
      _logger.e('PaystackService: Error getting transfer recipient: $e');
      return null;
    }
  }

  // Get banking details for a member (from members_bank_accounts table)
  Future<Map<String, dynamic>?> getMemberBankingDetails(String userId) async {
    try {
      final bankAccountResponse = await Supabase.instance.client
          .from('members_bank_accounts')
          .select(
            'paystack_recipient_code, account_type, branch_code, account_holder_name, bank_name, account_number',
          )
          .eq('user_id', userId)
          .eq('is_active', true)
          .maybeSingle();

      final recipientCode = bankAccountResponse?['paystack_recipient_code'];

      if (recipientCode == null || recipientCode.isEmpty) {
        _logger.i(
          'PaystackService: No recipient code found for member: $userId',
        );
        return null;
      }

      // Get recipient details from Paystack
      final recipientData = await getTransferRecipient(recipientCode);

      if (recipientData != null) {
        // Extract banking details from the correct location
        final details = recipientData['details'] as Map<String, dynamic>? ?? {};
        final accountNumber =
            details['account_number'] ??
            recipientData['recipient_account'] ??
            bankAccountResponse?['account_number'] ??
            '';

        // Return formatted banking details
        // Use FULL account number from Paystack for editing purposes
        final result = {
          'account_name':
              recipientData['name'] ??
              bankAccountResponse?['account_holder_name'] ??
              '',
          'account_number':
              accountNumber, // Use full account number from Paystack
          'bank_name': bankAccountResponse?['bank_name'] ?? '',
          'account_type': bankAccountResponse?['account_type'] ?? 'savings',
          'recipient_code': recipientCode,
          'branch_code': bankAccountResponse?['branch_code'] ?? '',
        };
        return result;
      }

      return null;
    } catch (e) {
      _logger.e('PaystackService: Error getting member banking details: $e');
      return null;
    }
  }

  // Get banking details for a user (not tied to a specific business)
  // Banking details are user-level, so we find any business owned by the user
  Future<Map<String, dynamic>?> getBankingDetailsForUser(String userId) async {
    try {
      final bankAccountResponse = await Supabase.instance.client
          .from('trusted_partner_bank_accounts')
          .select(
            'paystack_recipient_code, bank_account_type, branch_code, account_holder_name, bank_name, account_number',
          )
          .eq('user_id', userId)
          .eq('is_active', true)
          .maybeSingle();

      final recipientCode = bankAccountResponse?['paystack_recipient_code'];

      if (recipientCode == null || recipientCode.isEmpty) {
        _logger.i('PaystackService: No recipient code found for user: $userId');
        return null;
      }

      // Get recipient details from Paystack
      final recipientData = await getTransferRecipient(recipientCode);

      if (recipientData != null) {
        // Extract banking details from the correct location
        // Paystack nests the banking details under 'details' object
        final details = recipientData['details'] as Map<String, dynamic>? ?? {};
        final accountNumber =
            details['account_number'] ??
            recipientData['recipient_account'] ??
            bankAccountResponse?['account_number'] ??
            '';
        final bankCode =
            details['bank_code'] ?? recipientData['institution_code'] ?? '';
        final bankName = _getBankNameFromCode(bankCode);

        // Return formatted banking details
        // Use FULL account number from Paystack for editing purposes
        // (Supabase only stores masked version for security)
        final result = {
          'account_name':
              recipientData['name'] ??
              bankAccountResponse?['account_holder_name'] ??
              '',
          'account_number':
              accountNumber, // Use full account number from Paystack
          'bank_code': bankCode,
          'bank_name': bankName,
          'account_type':
              bankAccountResponse?['bank_account_type'] ??
              'savings', // Use stored account type from database
          'recipient_code': recipientCode,
          'branch_code':
              bankAccountResponse?['branch_code'] ??
              '', // Add branch code from database
        };
        return result;
      }

      return null;
    } catch (e) {
      _logger.e('PaystackService: Error getting banking details for user: $e');
      return null;
    }
  }

  // Helper method to get bank name from bank code
  String _getBankNameFromCode(String bankCode) {
    switch (bankCode) {
      case '632005':
        return 'Absa Bank';
      case '410506':
        return 'Access Bank';
      case '430000':
        return 'African Bank';
      case '584000':
        return 'African Business Bank';
      case '800000':
        return 'Albaraka Bank';
      case '686000':
        return 'Bank of China';
      case '888000':
        return 'Bank Zero';
      case '462005':
        return 'Bidvest Bank';
      case '470010':
        return 'Capitec Bank';
      case '450105':
        return 'Capitec Business';
      case '350005':
        return 'CitiBank';
      case '679000':
        return 'Discovery Bank';
      case '591000':
        return 'Finbond EPE';
      case '589000':
        return 'Finbond Mutual Bank';
      case '250655':
      case '253665': // Alternative FNB code
        return 'FNB';
      case '201419':
        return 'FirstRand Bank';
      case '570226':
        return 'HBZ Bank';
      case '587000':
        return 'HSBC';
      case '580105':
        return 'Investec';
      case '432000':
        return 'JP Morgan';
      case '198765':
        return 'Nedbank';
      case '585001':
        return 'Olympus Mobile';
      case '352000':
        return 'OM Bank';
      case '261251':
        return 'Rand Merchant Bank';
      case '222026':
        return 'RMB Private Bank';
      case '683000':
        return 'SASFIN Bank';
      case '351005':
        return 'Société Générale';
      case '410105':
        return 'South African Bank of Athens';
      case '051001':
        return 'Standard Bank';
      case '730020':
        return 'Standard Chartered';
      case '678910':
        return 'TymeBank';
      case '431010':
        return 'Ubank';
      case '588000':
        return 'VBS Mutual Bank';
      default:
        return 'Other';
    }
  }

  // Helper method to save recipient code to trusted_partner_bank_accounts table
  Future<void> _saveRecipientCodeToPartner(
    String businessId,
    String recipientCode,
    String accountType,
  ) async {
    try {
      // Find the user_id associated with this business_id
      final businessResponse = await Supabase.instance.client
          .from('businesses')
          .select('owner_member_id')
          .eq('id', businessId)
          .single();

      final userId = businessResponse['owner_member_id'];

      // Only update existing records - don't create new ones
      // The BankingDetailsDialog will handle creating records with complete data
      final existingRecord = await Supabase.instance.client
          .from('trusted_partner_bank_accounts')
          .select('id')
          .eq('user_id', userId)
          .eq('is_active', true)
          .maybeSingle();

      if (existingRecord != null) {
        // Update existing record with recipient code and account type
        await Supabase.instance.client
            .from('trusted_partner_bank_accounts')
            .update({
              'paystack_recipient_code': recipientCode,
              'bank_account_type': accountType,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', userId)
            .eq('is_active', true);

        _logger.i(
          'PaystackService: Updated recipient code and account type for existing record: business: $businessId, user: $userId',
        );
      } else {
        _logger.i(
          'PaystackService: No existing banking record found for user: $userId - BankingDetailsDialog will create complete record',
        );
      }
    } catch (e) {
      _logger.e('PaystackService: Error saving recipient code: $e');
      throw Exception('Failed to save recipient code: $e');
    }
  }

  // Payment method management methods (stub implementations)
  Future<List<Map<String, dynamic>>> getSavedPaymentMethods(
    String userId,
  ) async {
    try {
      // Get saved payment methods from members_card_details table
      final response = await Supabase.instance.client
          .from('members_card_details')
          .select(
            'authorization_code, card_type, last4, exp_month, exp_year, bank, brand, is_primary',
          )
          .eq('user_id', userId)
          .eq('is_active', true)
          .order('is_primary', ascending: false);

      return response
          .map<Map<String, dynamic>>(
            (card) => {
              'authorization_code': card['authorization_code'],
              'card_type': card['card_type'],
              'last4': card['last4'],
              'exp_month': card['exp_month'],
              'exp_year': card['exp_year'],
              'bank': card['bank'],
              'brand': card['brand'],
              'is_primary': card['is_primary'],
            },
          )
          .toList();
    } catch (e) {
      _logger.e('PaystackService: Error getting saved payment methods: $e');
      return [];
    }
  }

  /// Returns how many active (non-deleted) saved cards a member currently has.
  /// Used to enforce the [maxSavedCards] limit before adding a new card.
  Future<int> getActiveCardCount(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('members_card_details')
          .select('id')
          .eq('user_id', userId)
          .eq('is_active', true);
      return response.length;
    } catch (e) {
      _logger.e('PaystackService: Error counting saved cards: $e');
      return 0;
    }
  }

  Future<String?> getPrimaryPaymentMethod(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('members_card_details')
          .select('authorization_code')
          .eq('user_id', userId)
          .eq('is_primary', true)
          .eq('is_active', true)
          .maybeSingle();

      if (response != null) {
        _logger.i(
          'PaystackService: Found primary payment method for user: $userId',
        );
        return response['authorization_code'] as String?;
      }

      _logger.i(
        'PaystackService: No primary payment method found for user: $userId',
      );
      return null;
    } catch (e) {
      _logger.e('PaystackService: Error getting primary payment method: $e');
      return null;
    }
  }

  Future<void> deletePaymentMethod(
    String userId,
    String authorizationCode,
  ) async {
    try {
      final client = Supabase.instance.client;

      // Check whether the card being deleted is the member's primary card so
      // we can promote a replacement afterwards. Leaving a member with no
      // primary card would break subscription auto-renewal (which charges the
      // primary authorization).
      final target = await client
          .from('members_card_details')
          .select('is_primary')
          .eq('user_id', userId)
          .eq('authorization_code', authorizationCode)
          .eq('is_active', true)
          .maybeSingle();
      final wasPrimary = target != null && target['is_primary'] == true;

      // Soft delete by setting is_active to false
      await client
          .from('members_card_details')
          .update({
            'is_active': false,
            'is_primary': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId)
          .eq('authorization_code', authorizationCode);

      // If we just removed the primary card, promote the most recently added
      // remaining active card so the member always has a usable primary.
      if (wasPrimary) {
        final remaining = await client
            .from('members_card_details')
            .select('authorization_code')
            .eq('user_id', userId)
            .eq('is_active', true)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        final newPrimaryCode = remaining?['authorization_code'] as String?;
        if (newPrimaryCode != null && newPrimaryCode.isNotEmpty) {
          await setPrimaryPaymentMethod(userId, newPrimaryCode);
        }
      }

      _logger.i('PaystackService: Payment method deleted successfully');
    } catch (e) {
      _logger.e('PaystackService: Error deleting payment method: $e');
      throw Exception('Failed to delete payment method: $e');
    }
  }

  Future<void> setPrimaryPaymentMethod(
    String userId,
    String authorizationCode,
  ) async {
    try {
      // First, unset any existing primary
      await Supabase.instance.client
          .from('members_card_details')
          .update({
            'is_primary': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId)
          .eq('is_primary', true);

      // Then set the new primary
      await Supabase.instance.client
          .from('members_card_details')
          .update({
            'is_primary': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId)
          .eq('authorization_code', authorizationCode)
          .eq('is_active', true);

      _logger.i(
        'PaystackService: Set primary payment method: $authorizationCode',
      );
    } catch (e) {
      _logger.e('PaystackService: Error setting primary payment method: $e');
      throw Exception('Failed to set primary payment method: $e');
    }
  }

  Future<String?> chargeSavedCard({
    required String authorizationCode,
    required double amount,
    required String userId,
    required String userEmail,
    String? cvv,
    String? reference,
    String paymentType = 'subscription',
    String? subaccountCode,
    Map<String, dynamic>? extraMetadata,
  }) async {
    // In development mode, simulate successful payment
    if (_isDevelopmentMode) {
      _logger.i(
        'PaystackService: Development mode - Simulating successful saved card charge',
      );
      await Future.delayed(const Duration(seconds: 1));
      return 'success';
    }

    try {
      // Charge the saved card using Paystack's charge_authorization endpoint
      // NOTE: /transaction/charge_authorization is the correct endpoint for
      // reusable authorizations, not /charge (which is for direct charges)
      final Map<String, dynamic> body = {
        'authorization_code': authorizationCode,
        'email': userEmail,
        'amount': (amount * 100).round(), // Convert to kobo
        'currency': 'ZAR',
        'reference': reference ??
          'charge_${userId}_${DateTime.now().millisecondsSinceEpoch}',
        'metadata': {
          'user_id': userId,
          'payment_type': paymentType,
          if (extraMetadata != null) ...extraMetadata,
        },
      };

      // Include CVV for the charge if the member entered it (some card types
      // require CVV verification on charge_authorization).
      if (cvv != null && cvv.isNotEmpty) {
        body['cvv'] = cvv;
      }

      // Add subaccount for direct settlement to partner.
      // bearer='account' so Paystack fees come from the Local Lekker main
      // balance, not the subaccount — avoids ZAR settlement failure.
      if (subaccountCode != null && subaccountCode.isNotEmpty) {
        body['subaccount'] = subaccountCode;
        body['bearer'] = 'account';
      }

      final chargeResponse = await _proxyRequest(
        path: '/transaction/charge_authorization',
        method: 'POST',
        body: body,
      );

      if (chargeResponse.statusCode == 200) {
        final responseData = jsonDecode(chargeResponse.body);
        final status = responseData['data']['status'];

        if (status == 'success') {
          _logger.i('PaystackService: Saved card charged successfully');
          return 'success';
        } else {
          final gatewayResponse = responseData['data']?['gateway_response']
              as String? ?? responseData['message'] as String? ?? status;
          _logger.w(
            'PaystackService: Saved card charge failed: $gatewayResponse (status=$status)',
          );
          // Return the gateway message so the UI can surface it.
          return 'failed:$gatewayResponse';
        }
      } else {
        throw Exception('Failed to charge saved card: ${chargeResponse.body}');
      }
    } catch (e) {
      _logger.e('PaystackService: Error charging saved card: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> verifyTransaction(String reference) async {
    try {
      final response = await _proxyRequest(
        path: '/transaction/verify/$reference',
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final status = responseData['data']['status'];

        if (status == 'success') {
          final data = responseData['data'] as Map<String, dynamic>;
          // Helpful diagnostics to confirm settlement routing
          try {
            final amount = (data['amount'] ?? 0) as int; // in kobo
            final currency = data['currency'] ?? 'ZAR';
            final fees = data['fees'];
            final sub = data['subaccount'];
            final split = data['split'];
            final auth = data['authorization'] as Map<String, dynamic>?;
            final customer = data['customer'] as Map<String, dynamic>?;
            final ref = data['reference'];

            _logger.i('Paystack verify: status=success ref=$ref');
            _logger.i(
              '  amount=${(amount / 100).toStringAsFixed(2)} $currency fees=$fees',
            );
            _logger.i('  subaccount=$sub split=$split');
            _logger.d('  customer_code=${customer?['customer_code']}');
            _logger.d('  authorization_code=${auth?['authorization_code']}');
          } catch (e) {
            _logger.w('Paystack verify: logging extras failed: $e');
          }

          return data;
        } else {
          _logger.w(
            'PaystackService: Transaction verification failed with status: $status',
          );
          return null;
        }
      } else {
        throw Exception('Failed to verify transaction: ${response.body}');
      }
    } catch (e) {
      _logger.e('PaystackService: Error verifying transaction: $e');
      throw Exception('Failed to verify transaction: $e');
    }
  }

  Future<void> addPaymentMethod(
    String userId,
    String authorizationCode,
    Map<String, dynamic> cardDetails,
  ) async {
    try {
      final makePrimary = cardDetails['is_primary'] == true;
      final client = Supabase.instance.client;

      // Build the card payload once so the insert and the dedup-update paths
      // stay in sync.
      final cardPayload = <String, dynamic>{
        'card_type': cardDetails['card_type'] ?? 'card',
        'last4': cardDetails['last4'] ?? '****',
        'exp_month': cardDetails['exp_month'],
        'exp_year': cardDetails['exp_year'],
        'bank': cardDetails['bank'],
        'brand': cardDetails['brand'],
        'updated_at': DateTime.now().toIso8601String(),
      };

      // The partial unique index `members_card_details_user_primary`
      // (UNIQUE (user_id) WHERE is_primary = true) allows only ONE primary
      // card per user. Inserting a second row with is_primary=true throws a
      // unique-constraint violation. This bit members who already had a
      // primary card (e.g. the signup card) and then added another card and
      // marked it primary — the insert failed, so the new card was never
      // saved and the add-card flow appeared broken. Demote any existing
      // primary BEFORE inserting the new primary row so there is never more
      // than one primary at a time.
      if (makePrimary) {
        await client
            .from('members_card_details')
            .update({
              'is_primary': false,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', userId)
            .eq('is_primary', true);
      }

      // Dedup: if this exact Paystack authorization is already on file (active
      // or previously soft-deleted), reactivate/refresh it instead of inserting
      // a duplicate row. Paying with the same card twice must NOT create two
      // saved-card entries — that would both clutter the card picker and
      // wrongly count against the max-cards limit.
      final existing = await client
          .from('members_card_details')
          .select('id')
          .eq('user_id', userId)
          .eq('authorization_code', authorizationCode)
          .maybeSingle();

      if (existing != null) {
        await client
            .from('members_card_details')
            .update({
              ...cardPayload,
              'is_primary': makePrimary,
              'is_active': true,
            })
            .eq('id', existing['id']);
        _logger.i('PaystackService: Existing payment method refreshed');
        return;
      }

      // New card: enforce the max-cards limit before inserting. The database
      // also enforces this via a trigger as a defensive backstop, but checking
      // here lets us surface a clean, typed error to the UI.
      final activeCount = await getActiveCardCount(userId);
      if (activeCount >= maxSavedCards) {
        _logger.w(
          'PaystackService: Card limit reached ($activeCount/$maxSavedCards) '
          'for user $userId — refusing to add new card',
        );
        throw CardLimitException(maxSavedCards);
      }

      // Save payment method to members_card_details table
      await client.from('members_card_details').insert({
        'user_id': userId,
        'authorization_code': authorizationCode,
        ...cardPayload,
        'is_primary': makePrimary,
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
      });

      _logger.i('PaystackService: Payment method added successfully');
    } on CardLimitException {
      rethrow;
    } catch (e) {
      _logger.e('PaystackService: Error adding payment method: $e');
      throw Exception('Failed to add payment method: $e');
    }
  }

  /// Initialize a subscription payment with Paystack
  ///
  /// This method creates a subscription using a pre-configured plan code from
  /// the Paystack dashboard. The plan must be created in your Paystack account first.
  ///
  /// Plans enable auto-renewal - Paystack will automatically charge the customer
  /// on each billing cycle and send webhook notifications.
  ///
  /// [plan] - Name/identifier for internal tracking (e.g., 'monthly', 'annual')
  /// [amount] - Subscription amount in Rands (will be converted to kobo)
  /// [frequency] - Billing frequency in months (1 = monthly, 12 = annual)
  /// [userId] - User ID for tracking
  /// [userEmail] - Customer email for Paystack
  ///
  /// Returns the authorization URL to redirect user to for payment
  Future<Map<String, String>?> initializeSubscription({
    required String plan,
    required double amount,
    required int frequency,
    required String userId,
    required String userEmail,
    bool useCustomerCode = true,
  }) async {
    // In development mode, simulate successful subscription initialization
    if (_isDevelopmentMode) {
      _logger.i(
        'PaystackService: Development mode - Simulating subscription initialization',
      );
      await Future.delayed(const Duration(seconds: 1));
      return {'authorization_url': 'https://example.com/subscription/init', 'reference': 'dev_ref_${userId}'};
    }

    try {
      // Get the plan code from environment variables based on frequency
      String? planCode = _getPlanCode(frequency);

      if (planCode == null || planCode.isEmpty) {
        // No env-configured plan code — try to auto-create/fetch one on
        // Paystack (matches the original behaviour before the promo refactor).
        // This keeps real subscription auto-renewal working without requiring
        // PAYSTACK_MONTHLY_PLAN_CODE to be set in .env.
        _logger.w(
          'PaystackService: PAYSTACK_MONTHLY_PLAN_CODE not set — attempting '
          'to auto-create/fetch a Paystack plan for $plan ($frequency months).',
        );
        planCode = await _ensurePaystackPlan(
          plan: plan,
          amount: amount,
          frequency: frequency,
        );
      }

      if (planCode == null || planCode.isEmpty) {
        // Auto-create also failed — fall back to a one-off transaction so the
        // member can still pay. SubscriptionService.processManualPayment will
        // activate the 30-day local subscription on success. The member will
        // need to renew manually until a plan code is available.
        _logger.w(
          'PaystackService: Plan auto-create failed — falling back to one-off '
          'transaction. Add PAYSTACK_MONTHLY_PLAN_CODE to .env to re-enable '
          'Paystack-side auto-renewal.',
        );
        return await startOneTimePayment(
          itemName: 'Local Lekker $plan subscription',
          itemDescription: 'Local Lekker $plan subscription',
          amount: amount,
          userId: userId,
          userEmail: userEmail,
          useCustomerCode: useCustomerCode,
          extraMetadata: {
            'subscription_type': 'manual_renewal',
            'frequency': frequency,
            'plan_name': plan,
            'payment_type': 'subscription',
            'fallback_reason': 'no_plan_code_available',
          },
        );
      }

      _logger.i(
        'PaystackService: Initializing subscription with plan: $planCode, amount: ${(amount * 100).round()} kobo',
      );

      // For "new card" checkout, skip attaching existing customer_code so
      // Paystack opens the full card details form.
      String? customerCode;
      if (useCustomerCode) {
        // Ensure we have a named Paystack customer for proper dashboard display.
        customerCode = await _ensurePaystackCustomer(
          userId: userId,
          email: userEmail,
        );
      }

      // Generate the transaction reference upfront so we can return it
      final reference = 'sub_${userId}_${DateTime.now().millisecondsSinceEpoch}';

      // Initialize subscription using Paystack's subscription API
      final response = await _proxyRequest(
        path: '/transaction/initialize',
        method: 'POST',
        body: {
          'email': userEmail,
          'amount': (amount * 100).round(), // Convert to kobo (R99 = 9900 kobo)
          'plan': planCode, // Use the actual plan code from environment
          if (customerCode != null && customerCode.isNotEmpty)
            'customer': customerCode,
          'reference': reference,
          'callback_url':
              paystackCallbackUrl(),
          'channels': ['card'], // Enable card payments
          'metadata': {
            'user_id': userId,
            'subscription_type': 'recurring',
            'frequency': frequency,
            'plan_name': plan,
            'plan_code': planCode,
            'payment_type': 'subscription',
          },
          'customizations': _buildCheckoutCustomizations(
            title: 'Local Lekker',
            description: 'Complete your $plan membership checkout',
          ),
        },
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final authorizationUrl = responseData['data']['authorization_url'];

        _logger.i('PaystackService: Subscription initialized successfully with reference: $reference');
        return {'authorization_url': authorizationUrl, 'reference': reference};
      } else {
        // Parse the error for better diagnostics
        String errorDetail = response.body;
        String? parsedMessage;
        try {
          final errorData = jsonDecode(response.body);
          final errorMessage = errorData['message'] ?? errorData['error'] ?? '';
          final errorCode = errorData['code'] ?? '';
          parsedMessage = errorMessage.toString();
          if (errorCode == 'invalid_Key' || parsedMessage.contains('Invalid key')) {
            _logger.e(
              'PaystackService: INVALID KEY ERROR - The PAYSTACK_SECRET_KEY in Supabase Edge Function secrets is invalid. '
              'Please verify: 1) Key starts with sk_live_ or sk_test_, '
              '2) Key is not expired/revoked in Paystack Dashboard, '
              '3) Key was set correctly via: supabase secrets set PAYSTACK_SECRET_KEY=sk_live_xxx',
            );
            throw Exception(
              'Payment service configuration error. Please contact support. '
              '(Ref: invalid_api_key)',
            );
          }
        } catch (e) {
          if (e.toString().contains('invalid_api_key')) rethrow;
          // Could not parse error JSON, use raw body
        }

        // Tag errors so the UI layer can show accurate messages
        // (the proxy returns a synthetic 503 with this error text on real
        // network failures; everything else is a server / config issue).
        final isNetworkFailure = response.statusCode == 503 &&
            (parsedMessage?.toLowerCase().contains('connection failed') ?? false);
        final isAuthFailure = response.statusCode == 401;

        if (isNetworkFailure) {
          throw Exception(
            'Failed to initialize subscription: network_error - ${parsedMessage ?? 'Connection failed'}',
          );
        }
        if (isAuthFailure) {
          throw Exception(
            'Failed to initialize subscription: auth_error - ${parsedMessage ?? 'Session expired. Please sign in again.'}',
          );
        }
        throw Exception(
          'Failed to initialize subscription: server_error (${response.statusCode}) - ${parsedMessage?.isNotEmpty == true ? parsedMessage : errorDetail}',
        );
      }
    } catch (e) {
      _logger.e('PaystackService: Error initializing subscription: $e');
      // Preserve already-tagged messages so we don't double-wrap them
      if (e is Exception && e.toString().contains('Failed to initialize subscription')) {
        rethrow;
      }
      throw Exception('Failed to initialize subscription: unexpected_error - $e');
    }
  }

  /// Auto-create (or look up) a Paystack plan when no env-configured plan
  /// code is available. Mirrors the original behaviour of REV_01's
  /// `startSubscription` so subscription auto-renewal keeps working out of
  /// the box without requiring PAYSTACK_MONTHLY_PLAN_CODE in .env.
  ///
  /// Returns the plan code on success, or null if both creation and lookup
  /// fail (callers should fall back to a one-off transaction).
  Future<String?> _ensurePaystackPlan({
    required String plan,
    required double amount,
    required int frequency,
  }) async {
    final interval = frequency == 12
        ? 'annually'
        : frequency == 3
            ? 'quarterly'
            : frequency == 6
                ? 'biannually'
                : 'monthly';
    final planName = 'Local Lekker $plan Subscription';
    final amountKobo = (amount * 100).round();

    try {
      // Try to create the plan. Paystack accepts duplicate names but returns
      // an error code we can recover from by listing existing plans.
      final createResponse = await _proxyRequest(
        path: '/plan',
        method: 'POST',
        body: {
          'name': planName,
          'interval': interval,
          'amount': amountKobo,
          'currency': 'ZAR',
          'description': '$plan subscription plan',
        },
      );

      if (createResponse.statusCode == 200 || createResponse.statusCode == 201) {
        try {
          final data = jsonDecode(createResponse.body);
          final code = data['data']?['plan_code'] as String?;
          if (code != null && code.isNotEmpty) {
            _logger.i('PaystackService: Auto-created Paystack plan $code ($planName)');
            return code;
          }
        } catch (e) {
          _logger.w('PaystackService: Could not parse plan create response: $e');
        }
      } else {
        _logger.w(
          'PaystackService: Plan create returned ${createResponse.statusCode}: ${createResponse.body}',
        );
      }

      // Fall back to listing plans and finding ours by name + interval + amount.
      final listResponse = await _proxyRequest(
        path: '/plan?perPage=100',
      );

      if (listResponse.statusCode == 200) {
        final data = jsonDecode(listResponse.body);
        final plans = (data['data'] as List?) ?? const [];
        for (final p in plans) {
          if (p is Map &&
              p['name'] == planName &&
              p['interval'] == interval &&
              (p['amount'] as num?)?.toInt() == amountKobo) {
            final code = p['plan_code'] as String?;
            if (code != null && code.isNotEmpty) {
              _logger.i('PaystackService: Found existing Paystack plan $code ($planName)');
              return code;
            }
          }
        }
        // Loose match by name only as a last resort
        for (final p in plans) {
          if (p is Map && p['name'] == planName) {
            final code = p['plan_code'] as String?;
            if (code != null && code.isNotEmpty) {
              _logger.w(
                'PaystackService: Using loose-matched plan $code for $planName (amount/interval differ)',
              );
              return code;
            }
          }
        }
      } else {
        _logger.w(
          'PaystackService: Plan list returned ${listResponse.statusCode}: ${listResponse.body}',
        );
      }
    } catch (e) {
      _logger.e('PaystackService: _ensurePaystackPlan failed: $e');
    }
    return null;
  }

  /// Get the Paystack plan code from environment variables based on billing frequency
  String? _getPlanCode(int frequencyMonths) {
    try {
      switch (frequencyMonths) {
        case 1:
          return dotenv.env['PAYSTACK_MONTHLY_PLAN_CODE'];
        case 12:
          return dotenv.env['PAYSTACK_ANNUAL_PLAN_CODE'];
        default:
          _logger.w(
            'PaystackService: No plan code configured for $frequencyMonths months',
          );
          return null;
      }
    } catch (e) {
      _logger.e('PaystackService: Error getting plan code: $e');
      return null;
    }
  }

  /// Check subscription status from Paystack
  ///
  /// Returns subscription details including:
  /// - status: 'active', 'cancelled', 'expired'
  /// - next_payment_date: When the next charge will occur
  /// - amount: Subscription amount
  ///
  /// [subscriptionCode] - The subscription code from Paystack (SUB_xxxxx)
  Future<Map<String, dynamic>?> checkSubscriptionStatus(
    String subscriptionCode,
  ) async {
    if (_isDevelopmentMode) {
      _logger.i(
        'PaystackService: Development mode - Simulating subscription status check',
      );
      return {
        'status': 'active',
        'next_payment_date': DateTime.now()
            .add(const Duration(days: 30))
            .toIso8601String(),
        'amount': 9900,
      };
    }

    try {
      final response = await _proxyRequest(
        path: '/subscription/$subscriptionCode',
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        _logger.i(
          'PaystackService: Subscription status retrieved successfully',
        );
        return responseData['data'];
      } else {
        _logger.w(
          'PaystackService: Failed to get subscription status: ${response.body}',
        );
        return null;
      }
    } catch (e) {
      _logger.e('PaystackService: Error checking subscription status: $e');
      return null;
    }
  }

  /// Disable (cancel) a subscription
  ///
  /// This prevents future charges but allows the current billing period to complete.
  /// User retains access until the current period expires.
  ///
  /// [subscriptionCode] - The subscription code to cancel
  /// [emailToken] - Email token for the subscription (obtained from subscription details)
  Future<bool> cancelSubscription(
    String subscriptionCode,
    String emailToken,
  ) async {
    if (_isDevelopmentMode) {
      _logger.i(
        'PaystackService: Development mode - Simulating subscription cancellation',
      );
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    }

    try {
      final response = await _proxyRequest(
        path: '/subscription/disable',
        method: 'POST',
        body: {'code': subscriptionCode, 'token': emailToken},
      );

      if (response.statusCode == 200) {
        _logger.i('PaystackService: Subscription cancelled successfully');
        return true;
      } else {
        _logger.w(
          'PaystackService: Failed to cancel subscription: ${response.body}',
        );
        return false;
      }
    } catch (e) {
      _logger.e('PaystackService: Error cancelling subscription: $e');
      return false;
    }
  }

  /// Enable (reactivate) a previously cancelled subscription
  ///
  /// [subscriptionCode] - The subscription code to reactivate
  /// [emailToken] - Email token for the subscription
  Future<bool> reactivateSubscription(
    String subscriptionCode,
    String emailToken,
  ) async {
    if (_isDevelopmentMode) {
      _logger.i(
        'PaystackService: Development mode - Simulating subscription reactivation',
      );
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    }

    try {
      final response = await _proxyRequest(
        path: '/subscription/enable',
        method: 'POST',
        body: {'code': subscriptionCode, 'token': emailToken},
      );

      if (response.statusCode == 200) {
        _logger.i('PaystackService: Subscription reactivated successfully');
        return true;
      } else {
        _logger.w(
          'PaystackService: Failed to reactivate subscription: ${response.body}',
        );
        return false;
      }
    } catch (e) {
      _logger.e('PaystackService: Error reactivating subscription: $e');
      return false;
    }
  }

  /// Create a Paystack Subaccount for a trusted partner
  /// This allows split payments where the partner receives funds directly
  Future<String?> createSubaccount({
    required String businessName,
    required String bankCode,
    required String accountNumber,
    required String businessId,
    // IMPORTANT: percentageCharge on a Paystack subaccount is the COMMISSION
    // the PLATFORM charges the subaccount as a percentage of transaction amount.
    // If you do NOT want to take commission on partner sales, this MUST be 0.0.
    // Example: 10.0 means platform takes 10% commission; 0.0 means no commission.
    double percentageCharge = 0.0,
  }) async {
    // In development mode, simulate subaccount creation
    if (_isDevelopmentMode) {
      _logger.i(
        'PaystackService: Development mode - Simulating subaccount creation',
      );
      await Future.delayed(const Duration(milliseconds: 500));
      return 'ACCT_simulated_${DateTime.now().millisecondsSinceEpoch}';
    }

    try {
      _logger.i(
        'PaystackService: Creating subaccount for business: $businessName',
      );

      // Step 1: Verify the bank account using Account Number Resolution API
      // Note: Paystack only supports NGN, USD, GHS, KES for bank verification
      // For South African banks (ZAR), skip verification and create subaccount directly
      _logger.i(
        'PaystackService: Checking if bank verification is supported...',
      );
      if (kDebugMode) {
        print(
          '🔍 Paystack: Bank code $bankCode - Skipping verification (ZAR not supported by Paystack)',
        );
      }

      // South African banks - skip verification as Paystack doesn't support ZAR
      _logger.i(
        'PaystackService: Skipping bank verification for South African account',
      );
      if (kDebugMode) {
        print(
          '⚠️ Bank verification skipped - Paystack does not support ZAR currency verification',
        );
      }

      // Step 2: Create the subaccount
      if (kDebugMode) {
        print('🔨 Creating Paystack subaccount...');
      }
      if (kDebugMode) {
        print('   Business: $businessName');
      }
      if (kDebugMode) {
        print('   Bank Code: $bankCode');
      }
      if (kDebugMode) {
        print('   Account: $accountNumber');
      }
      if (kDebugMode) {
        print(
          '   Platform commission percentage (percentage_charge): $percentageCharge',
        );
      }

      final response = await _proxyRequest(
        path: '/subaccount',
        method: 'POST',
        body: {
          'business_name': businessName,
          'settlement_bank': bankCode,
          'account_number': accountNumber,
          'percentage_charge': percentageCharge,
          'description': 'Local Lekker Partner: $businessName',
          'metadata': {'business_id': businessId, 'platform': 'local_lekker'},
        },
      );

      if (kDebugMode) {
        print('🔨 Subaccount Creation Response: Status ${response.statusCode}');
      }
      if (kDebugMode) {
        print('🔨 Subaccount Creation Response: Body ${response.body}');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        final subaccountCode = responseData['data']['subaccount_code'];

        _logger.i(
          'PaystackService: Subaccount created successfully: $subaccountCode',
        );
        if (kDebugMode) {
          print('✅ Subaccount created: $subaccountCode');
        }
        return subaccountCode;
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['message'] ?? response.body;
        if (kDebugMode) {
          print('❌ Subaccount creation failed: $errorMessage');
        }
        throw Exception('Failed to create subaccount: $errorMessage');
      }
    } catch (e) {
      _logger.e('PaystackService: Error creating subaccount: $e');
      throw Exception('Failed to create subaccount: $e');
    }
  }

  /// Update an existing Paystack Subaccount
  Future<bool> updateSubaccount({
    required String subaccountCode,
    String? businessName,
    String? bankCode,
    String? accountNumber,
    double? percentageCharge,
  }) async {
    // In development mode, simulate success
    if (_isDevelopmentMode) {
      _logger.i(
        'PaystackService: Development mode - Simulating subaccount update',
      );
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    }

    try {
      _logger.i('PaystackService: Updating subaccount: $subaccountCode');

      final Map<String, dynamic> updateData = {};
      if (businessName != null) updateData['business_name'] = businessName;
      if (bankCode != null) updateData['settlement_bank'] = bankCode;
      if (accountNumber != null) updateData['account_number'] = accountNumber;
      if (percentageCharge != null) {
        updateData['percentage_charge'] = percentageCharge;
      }

      final response = await _proxyRequest(
        path: '/subaccount/$subaccountCode',
        method: 'PUT',
        body: updateData,
      );

      if (response.statusCode == 200) {
        _logger.i('PaystackService: Subaccount updated successfully');
        return true;
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
          'Failed to update subaccount: ${errorData['message'] ?? response.body}',
        );
      }
    } catch (e) {
      _logger.e('PaystackService: Error updating subaccount: $e');
      return false;
    }
  }

  /// Get Paystack Subaccount details
  Future<Map<String, dynamic>?> getSubaccount(String subaccountCode) async {
    // In development mode, simulate subaccount details
    if (_isDevelopmentMode) {
      _logger.i(
        'PaystackService: Development mode - Simulating subaccount retrieval',
      );
      await Future.delayed(const Duration(milliseconds: 500));
      return {
        'subaccount_code': subaccountCode,
        'business_name': 'Test Business',
        'percentage_charge': 90.0,
      };
    }

    try {
      _logger.i('PaystackService: Fetching subaccount: $subaccountCode');

      final response = await _proxyRequest(
        path: '/subaccount/$subaccountCode',
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData['data'];
      } else {
        _logger.w(
          'PaystackService: Failed to fetch subaccount: ${response.body}',
        );
        return null;
      }
    } catch (e) {
      _logger.e('PaystackService: Error fetching subaccount: $e');
      return null;
    }
  }

  /// Verify bank account details using Paystack's Account Number Resolution API
  /// This helps with automatic verification of bank accounts
  Future<Map<String, dynamic>?> verifyBankAccount({
    required String accountNumber,
    required String bankCode,
  }) async {
    // In development mode, simulate verification
    if (_isDevelopmentMode) {
      _logger.i(
        'PaystackService: Development mode - Simulating bank verification',
      );
      await Future.delayed(const Duration(milliseconds: 500));
      return {
        'account_number': accountNumber,
        'account_name': 'Test Account Name',
        'bank_id': 1,
      };
    }

    try {
      _logger.i(
        'PaystackService: Verifying bank account: $accountNumber with bank code: $bankCode',
      );

      final response = await _proxyRequest(
        path: '/bank/resolve?account_number=$accountNumber&bank_code=$bankCode',
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final accountData = responseData['data'];

        _logger.i(
          'PaystackService: Bank account verified - ${accountData['account_name']}',
        );
        return accountData;
      } else {
        final errorData = jsonDecode(response.body);
        _logger.w(
          'PaystackService: Failed to verify bank account: ${errorData['message']}',
        );
        return null;
      }
    } catch (e) {
      _logger.e('PaystackService: Error verifying bank account: $e');
      return null;
    }
  }

  /// Initialize payment for adding a payment method (card tokenization)
  /// This creates a small charge (R1.00) to tokenize the card
  Future<String?> initializePaymentMethod({
    required String userId,
    required String userEmail,
    int amount = 100, // Default R1.00 in kobo for tokenization
  }) async {
    // In development mode, simulate successful payment method initialization
    if (_isDevelopmentMode) {
      _logger.i(
        'PaystackService: Development mode - Simulating payment method initialization',
      );
      await Future.delayed(const Duration(milliseconds: 500));
      return 'https://example.com/payment-method/init';
    }

    try {
      // Initialize transaction for payment method
      final response = await _proxyRequest(
        path: '/transaction/initialize',
        method: 'POST',
        body: {
          'email': userEmail,
          'amount': amount, // R1.00 in kobo for card verification
          'reference': 'pm_${userId}_${DateTime.now().millisecondsSinceEpoch}',
          'callback_url': paystackCallbackUrl(),
          'metadata': {
            'user_id': userId,
            'payment_type': 'payment_method_setup',
            'purpose': 'card_tokenization',
          },
          'customizations': _buildCheckoutCustomizations(
            title: 'Local Lekker',
            description: 'Securely save your credit/debit card',
          ),
        },
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final authorizationUrl = responseData['data']['authorization_url'];

        _logger.i('PaystackService: Payment method initialization successful');
        return authorizationUrl;
      } else {
        throw Exception(
          'Failed to initialize payment method: ${response.body}',
        );
      }
    } catch (e) {
      _logger.e('PaystackService: Error initializing payment method: $e');
      throw Exception('Failed to initialize payment method: $e');
    }
  }

  Future<Map<String, dynamic>?> verifyStoredCard(
    String authorizationCode,
  ) async {
    // In development mode, simulate successful verification
    if (_isDevelopmentMode) {
      _logger.i(
        'PaystackService: Development mode - Simulating card verification',
      );
      await Future.delayed(const Duration(milliseconds: 500));
      return {
        'authorization_code': authorizationCode,
        'card_type': 'visa',
        'last4': '1234',
        'exp_month': 12,
        'exp_year': 2025,
        'bank': 'Test Bank',
        'brand': 'Visa',
        'reusable': true,
        'signature': 'simulated_signature',
        'verified': true,
      };
    }

    try {
      _logger.i(
        'PaystackService: Verifying stored card authorization: $authorizationCode',
      );

      // Use Paystack's verify authorization endpoint
      final response = await _proxyRequest(
        path: '/transaction/verify/$authorizationCode',
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final data = responseData['data'];

        if (data != null && data['authorization'] != null) {
          final authorization = data['authorization'];
          _logger.i(
            'PaystackService: Card authorization verified successfully',
          );

          return {
            'authorization_code': authorization['authorization_code'],
            'card_type': authorization['card_type'] ?? 'card',
            'last4': authorization['last4'],
            'exp_month': authorization['exp_month'],
            'exp_year': authorization['exp_year'],
            'bank': authorization['bank'] ?? '',
            'brand': authorization['brand'] ?? '',
            'reusable': authorization['reusable'] ?? true,
            'signature': authorization['signature'] ?? '',
            'verified': true,
          };
        } else {
          _logger.w('PaystackService: Authorization not found or invalid');
          return {'verified': false, 'error': 'Authorization not found'};
        }
      } else {
        final errorData = jsonDecode(response.body);
        _logger.e(
          'PaystackService: Card verification API error: ${errorData['message']}',
        );
        return {'verified': false, 'error': errorData['message']};
      }
    } catch (e) {
      _logger.e('PaystackService: Error verifying stored card: $e');
      return {'verified': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> tokenizeCard({
    required String cardNumber,
    required String expiryMonth,
    required String expiryYear,
    required String cvv,
    required String cardHolderName,
    required String userEmail,
    required String userId,
  }) async {
    try {
      // Parse expiry date - handle both MM/YY format and separate month/year
      String expMonth, expYear;
      if (expiryMonth.contains('/')) {
        // MM/YY format
        final expiryParts = expiryMonth.split('/');
        expMonth = expiryParts[0].padLeft(2, '0');
        expYear = '20${expiryParts[1]}';
      } else {
        // Separate month and year provided
        expMonth = expiryMonth.padLeft(2, '0');
        expYear = expiryYear.length == 2 ? '20$expiryYear' : expiryYear;
      }

      _logger.i('PaystackService: Tokenizing card for user: $userId');

      final response = await _proxyRequest(
        path: '/charge',
        method: 'POST',
        body: {
          'email': userEmail,
          'amount': 1, // 1 kobo (smallest amount) for tokenization only
          'card': {
            'number': cardNumber.replaceAll(' ', ''), // Remove spaces
            'cvv': cvv,
            'expiry_month': expMonth,
            'expiry_year': expYear,
          },
          'metadata': {
            'user_id': userId,
            'card_holder_name': cardHolderName,
            'tokenization_only':
                true, // Flag to indicate this is just for tokenization
          },
        },
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final data = responseData['data'];

        if (data['status'] == 'success') {
          final authorization = data['authorization'];
          _logger.i('PaystackService: Card tokenized successfully');

          return {
            'authorization_code': authorization['authorization_code'],
            'card_type': authorization['card_type'] ?? 'card',
            'last4': authorization['last4'],
            'exp_month': authorization['exp_month'],
            'exp_year': authorization['exp_year'],
            'bank': authorization['bank'] ?? '',
            'brand': authorization['brand'] ?? '',
            'reusable': authorization['reusable'] ?? true,
            'signature': authorization['signature'] ?? '',
          };
        } else {
          _logger.w(
            'PaystackService: Card tokenization failed with status: ${data['status']}',
          );
          return null;
        }
      } else {
        final errorData = jsonDecode(response.body);
        _logger.e(
          'PaystackService: Card tokenization API error: ${errorData['message']}',
        );
        throw Exception('Failed to tokenize card: ${errorData['message']}');
      }
    } catch (e) {
      _logger.e('PaystackService: Error tokenizing card: $e');
      throw Exception('Failed to tokenize card: $e');
    }
  }

  /// Test method to verify that card details are stored in Paystack
  /// This method simulates calling the Paystack verification API
  Future<Map<String, dynamic>> testVerifyStoredCard(
    String authorizationCode,
  ) async {
    _logger.i(
      'PaystackService: Testing verification of stored card with auth code: $authorizationCode',
    );

    try {
      // In development mode, simulate a successful verification
      if (_isDevelopmentMode) {
        _logger.i(
          'PaystackService: Development mode - simulating successful card verification',
        );

        // Simulate API delay
        await Future.delayed(const Duration(milliseconds: 500));

        return {
          'status': true,
          'message': 'Card verification successful (development mode)',
          'data': {
            'authorization_code': authorizationCode,
            'card_type': 'visa',
            'last4': '1234',
            'exp_month': '12',
            'exp_year': '2025',
            'bank': 'Test Bank',
            'brand': 'Visa',
            'reusable': true,
            'signature': 'test_signature_123',
            'verified': true,
          },
        };
      }

      // Production mode - make actual API call via server-side proxy
      _logger.d('PaystackService: Calling Paystack verify API for: $authorizationCode');

      final response = await _proxyRequest(
        path: '/transaction/verify/$authorizationCode',
      );

      _logger.d(
        'PaystackService: Verify API response status: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        _logger.i('PaystackService: Card verification successful');

        return {
          'status': true,
          'message': 'Card verification successful',
          'data': responseData['data'],
        };
      } else {
        final errorData = jsonDecode(response.body);
        _logger.w(
          'PaystackService: Card verification failed: ${errorData['message']}',
        );

        return {
          'status': false,
          'message': errorData['message'] ?? 'Verification failed',
          'data': null,
        };
      }
    } catch (e) {
      _logger.e('PaystackService: Error verifying stored card: $e');
      return {
        'status': false,
        'message': 'Error verifying card: $e',
        'data': null,
      };
    }
  }

  /// Fetch the most recent active subscription for a customer from Paystack.
  ///
  /// After a plan-based transaction succeeds, Paystack creates a subscription
  /// with a code like SUB_xxx. This method retrieves that code so it can be
  /// stored in the local database for webhook matching (auto-renewal, failure,
  /// cancellation events).
  ///
  /// [customerCodeOrEmail] - The Paystack customer_code (CUS_xxx) or email.
  /// [planCode] - Optional plan code to filter by (PLN_xxx).
  Future<String?> getCustomerSubscriptionCode({
    required String customerCodeOrEmail,
    String? planCode,
  }) async {
    if (_isDevelopmentMode) {
      _logger.i(
        'PaystackService: Development mode - returning simulated subscription code',
      );
      return 'SUB_dev_${DateTime.now().millisecondsSinceEpoch}';
    }

    try {
      // Fetch subscriptions for this customer
      final response = await _proxyRequest(
        path: '/subscription?customer=$customerCodeOrEmail&perPage=5',
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final subscriptions = responseData['data'] as List<dynamic>?;

        if (subscriptions == null || subscriptions.isEmpty) {
          _logger.w('PaystackService: No subscriptions found for customer');
          return null;
        }

        // Find the most recent active subscription, optionally matching plan
        for (final sub in subscriptions) {
          final status = sub['status'];
          final subPlan = sub['plan'];
          final subCode = sub['subscription_code'] as String?;

          if (status == 'active' || status == 'non-renewing' || status == 'attention') {
            if (planCode != null && subPlan != null) {
              final subPlanCode = subPlan['plan_code'] as String?;
              if (subPlanCode == planCode) {
                _logger.i(
                  'PaystackService: Found matching subscription: $subCode',
                );
                return subCode;
              }
            } else {
              _logger.i(
                'PaystackService: Found active subscription: $subCode',
              );
              return subCode;
            }
          }
        }

        // Fallback: return the first subscription code regardless of status
        final firstCode =
            subscriptions[0]['subscription_code'] as String?;
        _logger.i(
          'PaystackService: Using first subscription code: $firstCode',
        );
        return firstCode;
      } else {
        _logger.w(
          'PaystackService: Failed to fetch subscriptions: ${response.body}',
        );
        return null;
      }
    } catch (e) {
      _logger.w('PaystackService: Error fetching customer subscriptions: $e');
      return null;
    }
  }
}
