import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_lekker/services/supabase_service.dart';
import 'package:local_lekker/services/guest_analytics_service.dart';
import 'package:local_lekker/services/payment_status_service.dart';
import 'package:local_lekker/services/paystack_service.dart';
import 'package:local_lekker/services/subscription_service.dart';
import 'package:local_lekker/services/member_activation_service.dart';
import 'package:local_lekker/features/auth/welcome_page.dart';
import 'package:local_lekker/features/auth/password_reset_page.dart';
import 'package:local_lekker/features/auth/trusted_partner_home_page.dart';
import 'package:local_lekker/features/auth/members_home_page.dart';
import 'package:local_lekker/features/admin/admin_dashboard_screen.dart';
import 'package:local_lekker/features/payments/payments_feature.dart';
import 'package:local_lekker/features/auth/business_profile_page.dart';
import 'package:local_lekker/features/auth/member_profile_page.dart';
import 'package:local_lekker/features/trusted_partner/trusted_partner_terms_page.dart';
import 'package:local_lekker/features/member/member_terms_page.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  bool _isMemberProfileComplete(Map<String, dynamic>? profile) {
    if (profile == null) return false;

    String readValue(String key) => (profile[key] as String?)?.trim() ?? '';

    final createdAtRaw = profile['created_at'];
    final isLegacyProfile = createdAtRaw is String && (() {
      try {
        final createdAt = DateTime.parse(createdAtRaw);
        return createdAt.isBefore(DateTime(2025, 9, 24));
      } catch (_) {
        return false;
      }
    })();

    final coreFieldsComplete = readValue('name').isNotEmpty &&
        readValue('surname').isNotEmpty &&
        readValue('street').isNotEmpty &&
        readValue('suburb').isNotEmpty &&
        readValue('city').isNotEmpty &&
        readValue('province').isNotEmpty &&
        readValue('contact').isNotEmpty;

    if (!coreFieldsComplete) return false;

    if (isLegacyProfile) return true;

    return readValue('gender').isNotEmpty &&
        readValue('ethnicity').isNotEmpty &&
        readValue('date_of_birth').isNotEmpty;
  }

  Future<Map<String, dynamic>?> _getMemberProfile(String userId) async {
    try {
      return await SupabaseService.instance.getUserProfile(userId: userId);
    } catch (e) {
      if (kDebugMode) {
        print(
          'NavigationService._getMemberProfile ERROR: userId=$userId, error=$e',
        );
      }
      return null;
    }
  }

  /// Get subscription status for a user
  Future<String?> _getSubscriptionStatus(String userId) async {
    try {
      final subscription = await SubscriptionService().getSubscriptionStatus(
        userId,
      );
      final rawStatus =
          (subscription?['subscription_status'] ?? subscription?['status'])
              as String?;
      final status = rawStatus?.trim().toLowerCase();

      if (status == 'active') {
        return 'active';
      }

      // Attempt to recover a payment that succeeded at Paystack but was not
      // captured by the app (app closed / lost signal during checkout).
      // A brand-new signup has NO subscription row (subscription == null),
      // but a stale pre-activation row can also exist, so recover for any
      // non-active status. STRATEGY 1 (locally-saved reference) is always
      // safe; STRATEGY 2 (email lookup) is only allowed for members who have
      // never been activated, so a genuinely lapsed member is not re-activated
      // off an old successful payment.
      const preActivationStatuses = {
        'none',
        'pending',
        'incomplete',
        'processing',
        'initialized',
        '',
      };
      final allowEmailLookup = subscription == null ||
          status == null ||
          preActivationStatuses.contains(status);
      final recovered = await _tryRecoverPendingPayment(
        userId,
        allowEmailLookup: allowEmailLookup,
      );
      if (recovered) return 'active';

      return status ?? 'pending';
    } catch (e) {
      // Fallback path: if subscriptions table read fails (RLS/transient),
      // trust profiles.subscription when available so active members are not
      // incorrectly routed to payment.
      if (kDebugMode) {
        print(
          'NavigationService: Error checking subscription for userId=$userId: $e',
        );
      }

      // Fallback 1: read latest subscription row directly. This bypasses
      // service-level enrichment failures (e.g. QR/profile reads) so active
      // members are not downgraded to pending.
      try {
        final direct = await SupabaseService.instance.client
            .from('subscriptions')
            .select('status')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(1);
        if (direct.isNotEmpty) {
          final directStatus =
              (direct.first['status'] as String?)?.trim().toLowerCase();
          if (directStatus == 'active') {
            if (kDebugMode) {
              print(
                'NavigationService: Using direct subscriptions fallback status=active for userId=$userId',
              );
            }
            return 'active';
          }
          if (directStatus != null && directStatus.isNotEmpty) {
            return directStatus;
          }
        }
      } catch (directError) {
        if (kDebugMode) {
          print(
            'NavigationService: Direct subscriptions fallback failed for userId=$userId: $directError',
          );
        }
      }

      // Fallback 2: legacy profile subscription field.
      try {
        final profile = await SupabaseService.instance.getUserProfile(
          userId: userId,
        );
        final legacyStatus =
            (profile?['subscription'] as String?)?.trim().toLowerCase();
        if (legacyStatus == 'active') {
          if (kDebugMode) {
            print(
              'NavigationService: Using fallback profiles.subscription=active for userId=$userId',
            );
          }
          return 'active';
        }
      } catch (fallbackError) {
        if (kDebugMode) {
          print(
            'NavigationService: Fallback profile subscription check failed for userId=$userId: $fallbackError',
          );
        }
      }
      return 'pending';
    }
  }

  void _logMemberRoutingTrace({
    required String source,
    required String userId,
    String? email,
    String? role,
    bool? profileLoaded,
    bool? profileComplete,
    bool? memberTermsAccepted,
    String? subscriptionStatus,
    bool? isReactivation,
  }) {
    // TEMP TRACE: keep until member sign-in misrouting is fully resolved.
    Logger().i(
      'NAV_TRACE [$source] userId=$userId, email=${email ?? ''}, role=${role ?? 'null'}, '
      'profileLoaded=${profileLoaded?.toString() ?? 'null'}, '
      'profileComplete=${profileComplete?.toString() ?? 'null'}, '
      'memberTermsAccepted=${memberTermsAccepted?.toString() ?? 'null'}, '
      'subscriptionStatus=${subscriptionStatus ?? 'null'}, '
      'isReactivation=${isReactivation?.toString() ?? 'null'}',
    );
  }

  /// Public wrapper so payment screens can proactively self-heal (e.g. when a
  /// member returns to the "Complete Your Payment" screen after a successful
  /// but undetected charge). [allowEmailLookup] should be false for
  /// reactivation flows to avoid re-activating a lapsed member off an old
  /// successful payment.
  Future<bool> attemptPaymentRecovery(
    String userId, {
    bool allowEmailLookup = true,
  }) =>
      _tryRecoverPendingPayment(userId, allowEmailLookup: allowEmailLookup);

  /// Verify a saved transaction reference, retrying a few times to absorb the
  /// brief window where the bank has already deducted funds but Paystack has
  /// not yet finalized the (3DS) charge. Swallows transient errors so a single
  /// network blip never aborts recovery.
  Future<Map<String, dynamic>?> _verifyWithRetries(
    PaystackService paystackService,
    String reference,
    Logger logger, {
    int attempts = 3,
  }) async {
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final details = await paystackService.verifyTransaction(reference);
        if (details != null) return details;
      } catch (e) {
        logger.w(
          'NavigationService: verify attempt $attempt/$attempts failed for '
          '$reference: $e',
        );
      }
      if (attempt < attempts) {
        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }
    return null;
  }

  /// Attempt to recover a payment that succeeded at Paystack but was not
  /// processed by the app (e.g. user lost signal or closed the app).
  /// Returns true if a successful payment was found and the subscription
  /// was activated.
  Future<bool> _tryRecoverPendingPayment(
    String userId, {
    bool allowEmailLookup = true,
  }) async {
    final logger = Logger();
    try {
      final paystackService = PaystackService();

      // STRATEGY 1: Check for a saved transaction reference (from current update onwards)
      final pendingTx = await PaymentStatusService()
          .getPendingTransactionReference(userId);

      if (pendingTx != null) {
        final reference = pendingTx['reference']!;
        final planType = pendingTx['planType'] ?? 'subscription';

        logger.i(
          'NavigationService: Found pending transaction ref=$reference, verifying with Paystack...',
        );

        // Retry verification: the bank may have deducted funds before Paystack
        // finalizes the charge, so a single verify can transiently return null.
        final verifiedDetails =
            await _verifyWithRetries(paystackService, reference, logger);

        if (verifiedDetails != null) {
          logger.i('NavigationService: Payment CONFIRMED via saved reference!');
          return await _activateRecoveredPayment(
            userId: userId,
            planType: planType,
            verifiedDetails: verifiedDetails,
            paystackService: paystackService,
            logger: logger,
          );
        } else {
          // Keep the saved reference so a later attempt (screen self-heal /
          // next launch) can still recover once Paystack finalizes.
          logger.w('NavigationService: Saved transaction ref not successful at Paystack yet');
        }
      }

      // STRATEGY 2: No saved reference (member paid before this update) —
      // search Paystack for recent successful transactions by email.
      // Only for members who have never been activated (guards lapsed members).
      if (!allowEmailLookup) {
        logger.i(
          'NavigationService: Email-based recovery not allowed for this member '
          '(non-pre-activation status) — skipping.',
        );
        return false;
      }

      final user = SupabaseService.instance.getCurrentUser();
      final email = user?.email;
      if (email == null || email.isEmpty) return false;

      logger.i('NavigationService: No saved reference. Searching Paystack by email=$email...');

      final txData = await paystackService.findSuccessfulSubscriptionTransaction(email);
      if (txData == null) {
        logger.i('NavigationService: No successful Paystack transactions found for $email');
        return false;
      }

      // Verify this transaction belongs to THIS user via metadata.
      // Email alone is NOT sufficient proof of ownership: emails get reused
      // across deleted/recreated accounts, so a stale or foreign successful
      // payment must NEVER silently activate a brand-new signup. Require an
      // exact user_id match — if the transaction has no user_id, an empty one,
      // or a different one, do not auto-recover. The member must pay.
      final metadata = txData['metadata'] as Map<String, dynamic>? ?? {};
      final txUserId = metadata['user_id']?.toString();
      if (txUserId == null || txUserId.isEmpty || txUserId != userId) {
        logger.w(
          'NavigationService: Paystack tx user_id ($txUserId) does not match '
          'current user ($userId) — not auto-recovering. Routing to payment.',
        );
        return false;
      }

      logger.i('NavigationService: Found successful payment at Paystack via email lookup! ref=${txData['reference']}');

      return await _activateRecoveredPayment(
        userId: userId,
        planType: 'subscription',
        verifiedDetails: txData,
        paystackService: paystackService,
        logger: logger,
      );
    } catch (e) {
      Logger().e('NavigationService: Error during payment recovery: $e');
      return false;
    }
  }

  /// Shared logic to activate a subscription from a recovered Paystack payment.
  Future<bool> _activateRecoveredPayment({
    required String userId,
    required String planType,
    required Map<String, dynamic> verifiedDetails,
    required PaystackService paystackService,
    required Logger logger,
  }) async {
    logger.i('NavigationService: Activating subscription from recovered payment...');

    if (planType == 'promotion_intro') {
      final metadata =
          verifiedDetails['metadata'] as Map<String, dynamic>? ?? <String, dynamic>{};

      final promotionId = metadata['promotion_id']?.toString();
      final participantId = metadata['participant_id']?.toString();
      final freeMonths = int.tryParse(metadata['free_months']?.toString() ?? '') ?? 0;
      final initialChargeCents =
          int.tryParse(metadata['initial_charge_cents']?.toString() ?? '') ?? 100;
      final renewalChargeCents =
          int.tryParse(metadata['renewal_charge_cents']?.toString() ?? '') ?? 9900;
      final reference = verifiedDetails['reference']?.toString();

      if (promotionId == null || participantId == null) {
        logger.e('NavigationService: Missing promo metadata for recovered intro payment');
        return false;
      }

      final activated = await SubscriptionService().activateIntroCampaignSubscription(
        userId: userId,
        promotionId: promotionId,
        participantId: participantId,
        freeMonths: freeMonths,
        initialChargeCents: initialChargeCents,
        renewalChargeCents: renewalChargeCents,
        introChargeReference: reference,
      );

      if (activated) {
        await PaymentStatusService().clearPendingTransactionReference(userId);
        await PaymentStatusService().clearPendingPayment(userId);
      }
      return activated;
    }

    // Save card details if available
    try {
      final auth = verifiedDetails['authorization'] as Map<String, dynamic>?;
      if (auth != null) {
        final authorizationCode = auth['authorization_code'];
        if (authorizationCode != null && authorizationCode.toString().isNotEmpty) {
          final existing = await paystackService.getSavedPaymentMethods(userId);
          final shouldSetPrimary =
              existing.isEmpty || !existing.any((m) => m['is_primary'] == true);

          final cardDetails = {
            'card_type': auth['card_type'] ?? 'card',
            'last4': auth['last4'] ?? '****',
            'exp_month': auth['exp_month'],
            'exp_year': auth['exp_year'],
            'bank': auth['bank'],
            'brand': auth['brand'],
            'is_primary': shouldSetPrimary,
          };

          await paystackService.addPaymentMethod(userId, authorizationCode, cardDetails);
          if (shouldSetPrimary) {
            await paystackService.setPrimaryPaymentMethod(userId, authorizationCode);
          }
        }
      }

      // Save customer code
      final customer = verifiedDetails['customer'] as Map<String, dynamic>?;
      final customerCode = customer?['customer_code'] as String?;
      if (customerCode != null && customerCode.isNotEmpty) {
        await paystackService.savePaystackCustomerCode(
          userId: userId,
          customerCode: customerCode,
        );
      }
    } catch (e) {
      logger.w('NavigationService: Error saving card/customer during recovery: $e');
      // Continue - card saving is not critical for subscription activation
    }

    // Retrieve Paystack subscription code for webhook matching
    String? paystackSubscriptionCode;
    try {
      final customerCode = await paystackService.getPaystackCustomerCode(userId);
      if (customerCode != null && customerCode.isNotEmpty) {
        paystackSubscriptionCode = await paystackService.getCustomerSubscriptionCode(
          customerCodeOrEmail: customerCode,
        );
      }
    } catch (e) {
      logger.w('NavigationService: Could not retrieve subscription code during recovery: $e');
    }

    // Activate subscription
    final success = await SubscriptionService().processManualPayment(
      userId: userId,
      planType: planType,
      paystackSubscriptionCode: paystackSubscriptionCode,
    );

    if (success) {
      // Clear any pending references
      await PaymentStatusService().clearPendingTransactionReference(userId);
      await PaymentStatusService().clearPendingPayment(userId);
      logger.i('NavigationService: Payment recovery successful! Subscription activated.');
      return true;
    } else {
      logger.e('NavigationService: processManualPayment returned false during recovery');
      return false;
    }
  }

  /// Determine the appropriate initial screen based on member authentication and role
  Future<Widget> getInitialScreen() async {
    // Password-reset deep links are resolved by AppInitializer before this call.
    if (SupabaseService.instance.getCurrentUser() == null) {
      return const MembersHomePage();
    }
    final logger = Logger();

    // FIRST: Check if user has an active password recovery session
    try {
      logger.i('NavigationService: Checking for active recovery sessions...');
      final response = await SupabaseService.instance.client
          .from('recovery_sessions')
          .select()
          .eq('used', false)
          .gt('expires_at', DateTime.now().toIso8601String())
          .limit(1);

      logger.i(
        'NavigationService: Recovery session query returned: ${response.length} results',
      );

      if (response.isNotEmpty) {
        logger.i(
          'NavigationService: Active recovery session found - showing PasswordResetPage',
        );
        final recoveryData = response[0];
        final token = recoveryData['token'] ?? '';

        // Mark as used
        try {
          await SupabaseService.instance.client
              .from('recovery_sessions')
              .update({'used': true})
              .eq('id', recoveryData['id']);
          logger.i('NavigationService: Recovery session marked as used');
        } catch (e) {
          logger.w('Failed to mark recovery session as used: $e');
        }

        // Return PasswordResetPage
        return PasswordResetPage(accessToken: token, refreshToken: null);
      }
    } catch (e) {
      final logger = Logger();
      logger.e('NavigationService: Error checking recovery session: $e');
      // Continue with normal auth flow
    }

    // Check authentication status
    try {
      final member = SupabaseService.instance.getCurrentUser();

      if (member == null) {
        return const MembersHomePage();
      }

      // Check if user is deactivated before proceeding
      try {
        final profileData = await SupabaseService.instance.client
            .from('profiles')
            .select('is_deactivated')
            .eq('id', member.id)
            .maybeSingle();

        if (profileData != null && profileData['is_deactivated'] == true) {
          // Admins are never subject to the payment/reactivation flow
          final roleCheck = await SupabaseService.instance.getUserRole(
            userId: member.id,
          );
          if (roleCheck?.toLowerCase() == 'admin') {
            return const AdminDashboardScreen();
          }
          logger.w(
            'NavigationService: User is deactivated - redirecting to reactivation flow',
          );
          return const PaymentRequiredScreen(isReactivation: true);
        }
      } catch (e) {
        logger.w('NavigationService: Error checking deactivation status: $e');
        // Continue with normal flow if check fails
      }

      // Member is authenticated, check their role
      // Note: profile check is skipped here to avoid false sign-outs due to
      // RLS propagation delays or transient network errors right after sign-in.
      final role = await SupabaseService.instance.getUserRole(
        userId: member.id,
      );

      // If we can't determine role at all, do a profile check as a fallback
      if (role == null) {
        final profile = await _getMemberProfile(member.id);
        if (profile == null) {
          // Distinguish a genuinely missing profile (deleted account / stale
          // "ghost" session) from a transient read error. Only force sign-out
          // when the row is definitively absent, so we never log users out on
          // transient RLS/network blips.
          bool profileDefinitelyMissing = false;
          try {
            final probe = await SupabaseService.instance.client
                .from('profiles')
                .select('id')
                .eq('id', member.id)
                .maybeSingle();
            profileDefinitelyMissing = probe == null;
          } catch (_) {
            profileDefinitelyMissing = false;
          }
          if (profileDefinitelyMissing) {
            if (kDebugMode) {
              print(
                'NavigationService.getInitialScreen: Profile row missing for ${member.id} - clearing stale session',
              );
            }
            await SupabaseService.instance.signOut();
            return const MembersHomePage();
          }
          if (kDebugMode) {
            print(
              'NavigationService.getInitialScreen: No role and no profile for user ${member.id} - returning welcome without clearing session',
            );
          }
          return const WelcomePage();
        }
        if (!_isMemberProfileComplete(profile)) {
          return const MemberProfilePage();
        }
      }

      if (kDebugMode) {
        print(
          'NavigationService.getInitialScreen: userId=${member.id}, role=$role',
        );
      }

      // Route based on member role
      switch (role?.toLowerCase()) {
        case 'admin':
          if (kDebugMode) {
            print(
              'NavigationService.getInitialScreen: Routing to AdminDashboardScreen',
            );
          }
          return const AdminDashboardScreen();

        case 'trusted_partner':
          // If trusted partner has not completed business setup, force them to BusinessProfilePage
          final isComplete = await SupabaseService.instance
              .isBusinessProfileComplete(member.id);
          if (!isComplete) {
            return const BusinessProfilePage();
          }
          // Check partner terms acceptance before proceeding; if also a member, ensure member terms too
          final profile = await SupabaseService.instance.getUserProfile(
            userId: member.id,
          );
          final partnerAccepted = (profile?['partner_terms_accepted'] == true);
          if (!partnerAccepted) {
            return const TrustedPartnerTermsPage();
          }
          // If this trusted partner is also a member, require member terms acceptance
          final bool isAlsoMember = profile?['is_tp_member'] == true;
          if (isAlsoMember) {
            final memberAccepted = await SupabaseService.instance
                .hasMemberAcceptedTerms(member.id);
            if (!memberAccepted) {
              return const MemberTermsPage();
            }
          }
          return const TrustedPartnerHomePage();

        case 'member':
        default:
          // Parallelize the independent member fetches (profile + subscription)
          // to cut sequential round-trips. Terms reuse the loaded profile below.
          final memberFetches = await Future.wait([
            _getMemberProfile(member.id),
            _getSubscriptionStatus(member.id),
          ]);
          final profile = memberFetches[0] as Map<String, dynamic>?;
          final subscriptionStatus = memberFetches[1] as String?;
          final profileLoaded = profile != null;
          final profileComplete =
              profileLoaded ? _isMemberProfileComplete(profile) : null;
          // Only force profile completion when we can actually read profile data.
          // If profile read fails (e.g. transient DB/RLS issue), continue with
          // terms/subscription routing so existing members are not blocked.
          if (profileLoaded && profileComplete == false) {
            _logMemberRoutingTrace(
              source: 'getInitialScreen',
              userId: member.id,
              email: member.email,
              role: role,
              profileLoaded: profileLoaded,
              profileComplete: profileComplete,
            );
            return const MemberProfilePage();
          }
          // Browse-free model: members with a complete profile can use the
          // app without accepting terms or paying. Terms + payment are only
          // required when they opt to activate or request a deal.
          _logMemberRoutingTrace(
            source: 'getInitialScreen',
            userId: member.id,
            email: member.email,
            role: role,
            profileLoaded: profileLoaded,
            profileComplete: profileComplete,
            subscriptionStatus: subscriptionStatus,
          );
          return const MembersHomePage();
      }
    } catch (e) {
      // On error, check if user is still authenticated before falling back to welcome
      if (kDebugMode) {
        print('NavigationService: Error determining initial screen: $e');
      }
      final currentUser = SupabaseService.instance.getCurrentUser();
      if (currentUser == null) {
        return const MembersHomePage();
      }
      // User is authenticated but something went wrong - show a safe default
      // based on what we know from the error context rather than signing them out
      if (kDebugMode) {
        print('NavigationService: User is authenticated despite error - retrying role check');
      }
      try {
        final role = await SupabaseService.instance.getUserRole(userId: currentUser.id);
        if (role?.toLowerCase() == 'trusted_partner') return const TrustedPartnerHomePage();
        if (role?.toLowerCase() == 'admin') return const AdminDashboardScreen();
        return const MembersHomePage();
      } catch (_) {
        return const WelcomePage();
      }
    }
  }

  /// Navigate to appropriate home page after successful authentication
  Future<void> navigateToHomeAfterAuth(BuildContext context) async {
    try {
      final member = SupabaseService.instance.getCurrentUser();
      if (member == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MembersHomePage()),
        );
        return;
      }
      unawaited(GuestAnalyticsService().linkConversion());

      final role = await SupabaseService.instance.getUserRole(
        userId: member.id,
      );

      // If we can't determine role, do a profile check as a fallback
      if (role == null) {
        final profile = await _getMemberProfile(member.id);
        if (profile == null) {
          if (kDebugMode) {
            print(
              'NavigationService.navigateToHomeAfterAuth: No role and no profile for user ${member.id} - returning welcome without clearing session',
            );
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const WelcomePage()),
          );
          return;
        }
        if (!_isMemberProfileComplete(profile)) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MemberProfilePage()),
          );
          return;
        }
      }
      Widget homePage;

      switch (role?.toLowerCase()) {
        case 'admin':
          homePage = const AdminDashboardScreen();
          break;
        case 'trusted_partner':
          // Check business completion and route accordingly
          final isComplete = await SupabaseService.instance
              .isBusinessProfileComplete(member.id);
          if (!isComplete) {
            homePage = const BusinessProfilePage();
          } else {
            final profile = await SupabaseService.instance.getUserProfile(
              userId: member.id,
            );
            final accepted = (profile?['partner_terms_accepted'] == true);
            homePage = accepted
                ? const TrustedPartnerHomePage()
                : const TrustedPartnerTermsPage();
          }
          break;
        case 'member':
        default:
          // Parallelize the independent member fetches (profile + subscription).
          final memberFetches = await Future.wait([
            _getMemberProfile(member.id),
            _getSubscriptionStatus(member.id),
          ]);
          final profile = memberFetches[0] as Map<String, dynamic>?;
          final subscriptionStatus = memberFetches[1] as String?;
          final profileLoaded = profile != null;
          final profileComplete =
              profileLoaded ? _isMemberProfileComplete(profile) : null;
          if (profileLoaded && profileComplete == false) {
            _logMemberRoutingTrace(
              source: 'navigateToHomeAfterAuth',
              userId: member.id,
              email: member.email,
              role: role,
              profileLoaded: profileLoaded,
              profileComplete: profileComplete,
            );
            homePage = const MemberProfilePage();
            break;
          }
          // Browse-free model: terms are not forced here; they are collected
          // when the member opts to pay. New members (no subscription yet)
          // get a one-time, skippable activation offer after signup.
          final isActive = subscriptionStatus == 'active';
          var showActivationOffer = false;
          if (!isActive && subscriptionStatus == null) {
            final activation = MemberActivationService();
            if (!await activation.wasActivationOfferShown(member.id)) {
              await activation.markActivationOfferShown(member.id);
              showActivationOffer = true;
            }
          }

          _logMemberRoutingTrace(
            source: 'navigateToHomeAfterAuth',
            userId: member.id,
            email: member.email,
            role: role,
            profileLoaded: profileLoaded,
            profileComplete: profileComplete,
            subscriptionStatus: subscriptionStatus,
          );

          homePage = showActivationOffer
              ? const PaymentRequiredScreen(allowSkip: true)
              : const MembersHomePage();
          break;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => homePage),
      );
    } catch (e) {
      // Fallback to welcome page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
    }
  }

  /// Navigate to home page after successful payment
  /// Navigate to appropriate home page after successful payment
  Future<void> navigateToHomeAfterPayment(BuildContext context) async {
    try {
      final member = SupabaseService.instance.getCurrentUser();
      if (member == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MembersHomePage()),
        );
        return;
      }

      final role = await SupabaseService.instance.getUserRole(
        userId: member.id,
      );

      // If we can't determine role, do a profile check as a fallback
      if (role == null) {
        final profile = await _getMemberProfile(member.id);
        if (profile == null) {
          if (kDebugMode) {
            print(
              'NavigationService.navigateToHomeAfterPayment: No role and no profile for user ${member.id} - returning welcome without clearing session',
            );
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const WelcomePage()),
          );
          return;
        }
        if (!_isMemberProfileComplete(profile)) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MemberProfilePage()),
          );
          return;
        }
      }

      Widget homePage;

      switch (role?.toLowerCase()) {
        case 'admin':
          homePage = const AdminDashboardScreen();
          break;
        case 'trusted_partner':
          // On payment flow routing, also respect business completion
          final isComplete = await SupabaseService.instance
              .isBusinessProfileComplete(member.id);
          if (!isComplete) {
            homePage = const BusinessProfilePage();
          } else {
            final profile = await SupabaseService.instance.getUserProfile(
              userId: member.id,
            );
            final accepted = (profile?['partner_terms_accepted'] == true);
            homePage = accepted
                ? const TrustedPartnerHomePage()
                : const TrustedPartnerTermsPage();
          }
          break;
        case 'member':
        default:
          final profile = await _getMemberProfile(member.id);
          if (profile != null && !_isMemberProfileComplete(profile)) {
            homePage = const MemberProfilePage();
            break;
          }
          // On payment completion, still enforce member terms acceptance if somehow not yet accepted
          final memberAccepted = await SupabaseService.instance
              .hasMemberAcceptedTerms(member.id);
          if (!memberAccepted) {
            homePage = const MemberTermsPage();
          } else {
            // Verify subscription is truly active before showing home page.
            // If processManualPayment failed but user was navigated here
            // anyway, redirect back to PaymentRequiredScreen instead of
            // letting the user land on a broken home page.
            final subStatus = await _getSubscriptionStatus(member.id);
            homePage = subStatus == 'active'
                ? const MembersHomePage()
                : const PaymentRequiredScreen(allowSkip: true);
          }
          break;
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => homePage),
        (route) => false,
      );
    } catch (e) {
      // On error, fall back to member home page
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const MembersHomePage()),
        (route) => false,
      );
    }
  }
}
