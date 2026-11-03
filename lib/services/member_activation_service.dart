import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/member/member_terms_page.dart';
import '../features/auth/welcome_page.dart';
import '../features/payments/payments_feature.dart';
import 'guest_analytics_service.dart';
import 'supabase_service.dart';

/// Gatekeeper for the "browse free, pay to save" member model.
///
/// Guests and members can browse deals without a subscription. Requesting a
/// deal needs sign-in and an active subscription (or TP membership). Member
/// terms are collected at the moment the member opts to pay.
class MemberActivationService {
  static final MemberActivationService _instance =
      MemberActivationService._internal();
  factory MemberActivationService() => _instance;
  MemberActivationService._internal();

  final Logger _logger = Logger();

  static const Color _kBrandGreen = Color(0xFF3C8C44);
  static const String _offerShownKeyPrefix = 'activation_offer_shown_';

  /// Mirrors the check in DealAuthorizationService.requestDealAuthorization.
  Future<bool> canRequestDeals(String userId) async {
    final client = SupabaseService.instance.client;
    try {
      final profile = await client
          .from('profiles')
          .select('is_tp_member')
          .eq('id', userId)
          .maybeSingle();
      if (profile?['is_tp_member'] == true) return true;

      final rows = await client
          .from('subscriptions')
          .select('current_period_end')
          .eq('user_id', userId)
          .eq('status', 'active')
          .order('current_period_end', ascending: false)
          .limit(1);
      if (rows.isEmpty) return false;

      final periodEnd = rows.first['current_period_end'] as String?;
      if (periodEnd == null) return true;
      final expiry = DateTime.tryParse(periodEnd);
      return expiry == null || expiry.isAfter(DateTime.now());
    } catch (e) {
      _logger.w('MemberActivationService.canRequestDeals failed: $e');
      // Let the request proceed; DealAuthorizationService re-checks and
      // surfaces a proper error if the member is not allowed.
      return true;
    }
  }

  /// Returns true when the member may submit the deal request now. Otherwise
  /// opens sign-in for guests or the activation popup for inactive members.
  Future<bool> ensureCanRequestDeal(
    BuildContext context, {
    double? savings,
    String? dealId,
  }) async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) {
      if (dealId != null) {
        unawaited(
          GuestAnalyticsService().recordDealRequest(dealId, savings: savings),
        );
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WelcomePage(potentialSavings: savings),
        ),
      );
      return false;
    }
    if (await canRequestDeals(user.id)) return true;
    if (!context.mounted) return false;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ActivateToSaveDialog(savings: savings),
    );
    if (proceed == true && context.mounted) {
      await startActivation(context, potentialSavings: savings);
    }
    return false;
  }

  /// Terms → subscription payment, launched from an in-app prompt.
  Future<void> startActivation(
    BuildContext context, {
    double? potentialSavings,
  }) async {
    if (!await ensureTermsAccepted(context)) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentRequiredScreen(
          allowSkip: true,
          potentialSavings: potentialSavings,
        ),
      ),
    );
  }

  /// Shows the member terms (pop-back mode) if not yet accepted. Returns true
  /// only once the member has accepted.
  Future<bool> ensureTermsAccepted(BuildContext context) async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return false;
    if (await SupabaseService.instance.hasMemberAcceptedTerms(user.id)) {
      return true;
    }
    if (!context.mounted) return false;
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const MemberTermsPage(popOnAccept: true)),
    );
    return accepted == true;
  }

  /// Whether the optional "activate now" screen was already offered to this
  /// member on this device after signup.
  Future<bool> wasActivationOfferShown(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_offerShownKeyPrefix$userId') ?? false;
  }

  Future<void> markActivationOfferShown(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_offerShownKeyPrefix$userId', true);
  }

  static String formatSavings(double value) => 'R${value.toStringAsFixed(2)}';
}

class _ActivateToSaveDialog extends StatelessWidget {
  final double? savings;

  const _ActivateToSaveDialog({this.savings});

  @override
  Widget build(BuildContext context) {
    final hasSavings = savings != null && savings! > 0;
    const green = MemberActivationService._kBrandGreen;

    return AlertDialog(
      title: const Text(
        'Complete subscription to save',
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.savings_outlined, size: 56, color: green),
          const SizedBox(height: 12),
          if (hasSavings) ...[
            const Text('You will save', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              MemberActivationService.formatSavings(savings!),
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: green,
              ),
            ),
            const SizedBox(height: 4),
            const Text('on this deal', style: TextStyle(fontSize: 15)),
          ] else
            const Text(
              'Activate your membership to unlock the savings on this deal.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15),
            ),
          const SizedBox(height: 16),
          Text(
            'Activate your Local Lekker membership (R99/month) to request '
            'this deal. It only takes a minute.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
          ),
          child: const Text('Proceed'),
        ),
      ],
    );
  }
}
