import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:local_lekker/services/paystack_service.dart';
import 'package:local_lekker/services/supabase_service.dart';
import 'package:local_lekker/services/payment_status_service.dart';
import 'package:local_lekker/services/subscription_service.dart';
import 'package:local_lekker/features/auth/welcome_page.dart';
import 'package:local_lekker/services/navigation_service.dart';
import 'package:local_lekker/services/deep_link_service.dart';
import 'package:local_lekker/services/promotion_campaign_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';
import 'package:local_lekker/features/payments/paystack_webview_page.dart';
import 'package:local_lekker/features/member/member_terms_page.dart';
import 'package:flutter/foundation.dart';
import 'package:local_lekker/features/auth/widgets/trusted_partner_key_dialog.dart';
import 'package:local_lekker/services/web_checkout.dart';
// Removed direct MembersHomePage import to enforce centralized gating

class PaymentRequiredScreen extends StatefulWidget {
  final bool isReactivation;

  const PaymentRequiredScreen({
    super.key,
    this.isReactivation = false,
  });

  @override
  State<PaymentRequiredScreen> createState() => _PaymentRequiredScreenState();
}

class _PaymentRequiredScreenState extends State<PaymentRequiredScreen> {
  bool _loadingCampaign = true;
  Map<String, dynamic>? _eligibleIntroCampaign;
  bool _isPaymentFailed = false;

  // Self-heal: a member can reach this screen after a payment that succeeded
  // at the bank/Paystack but was not captured by the app (app closed / lost
  // signal during checkout). Proactively look for that payment so they don't
  // have to sign out/in or pay again.
  bool _verifyingPayment = true;
  Timer? _recoveryPollTimer;
  int _recoveryPolls = 0;
  static const int _maxRecoveryPolls = 6;

  @override
  void initState() {
    super.initState();
    _checkTermsAcceptance();
    _loadEligibleIntroCampaign();
    _loadPaymentFailureState();
    _runInitialPaymentRecovery();
  }

  @override
  void dispose() {
    _recoveryPollTimer?.cancel();
    super.dispose();
  }

  /// First-pass recovery, shown with a "Verifying your payment…" overlay.
  /// If a successful-but-undetected payment is found, route straight home.
  /// Otherwise reveal the payment options and keep polling briefly in the
  /// background in case Paystack finalizes the charge while the member reads
  /// the screen.
  Future<void> _runInitialPaymentRecovery() async {
    final recovered = await _attemptRecoveryOnce();
    if (!mounted) return;
    if (recovered) {
      await NavigationService().navigateToHomeAfterPayment(context);
      return;
    }
    setState(() => _verifyingPayment = false);
    _startBackgroundRecoveryPoll();
  }

  Future<bool> _attemptRecoveryOnce() async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) return false;
      // Email lookup is only safe for first-time activation, never for a
      // reactivation flow (would re-activate off an old successful payment).
      return await NavigationService().attemptPaymentRecovery(
        user.id,
        allowEmailLookup: !widget.isReactivation,
      );
    } catch (_) {
      return false;
    }
  }

  void _startBackgroundRecoveryPoll() {
    _recoveryPollTimer?.cancel();
    _recoveryPollTimer =
        Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted || _recoveryPolls >= _maxRecoveryPolls) {
        timer.cancel();
        return;
      }
      _recoveryPolls++;
      final recovered = await _attemptRecoveryOnce();
      if (!mounted) return;
      if (recovered) {
        timer.cancel();
        await NavigationService().navigateToHomeAfterPayment(context);
      }
    });
  }

  Future<void> _loadPaymentFailureState() async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) return;

      final role = await SupabaseService.instance.getUserRole(userId: user.id);
      final profile = await SupabaseService.instance.getUserProfile(
        userId: user.id,
      );
      final isTpMember = profile?['is_tp_member'] == true;

      if (role?.toLowerCase() == 'trusted_partner' || isTpMember) {
        if (!mounted) return;
        setState(() {
          _isPaymentFailed = false;
        });
        return;
      }

      final subscription = await SubscriptionService().getSubscriptionStatus(
        user.id,
      );
      final status =
          (subscription?['subscription_status'] ?? subscription?['status'])
              ?.toString()
              .trim()
              .toLowerCase();

      if (!mounted) return;
      setState(() {
        _isPaymentFailed = status == 'payment_failed' || status == 'failed';
      });
    } catch (_) {
      // Keep default false if status cannot be loaded.
    }
  }

  void _openStandardPaymentOption() {
    const selectedPlan = 'subscription';
    const planDetails = {
      'name': 'Subscription',
      'price': 99,
      'description': 'Monthly subscription',
      'frequency': 1,
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentOptionsScreen(
          selectedPlan: selectedPlan,
          planDetails: planDetails,
          userId: SupabaseService.instance.getCurrentUser()?.id,
        ),
      ),
    );
  }

  Future<void> _loadEligibleIntroCampaign() async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      final email = user?.email;
      if (user == null || email == null || email.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _loadingCampaign = false;
          });
        }
        return;
      }

      final eligible = await PromotionCampaignService().getEligibleIntroCampaign(
        email: email,
      );

      if (mounted) {
        setState(() {
          _eligibleIntroCampaign = eligible;
          _loadingCampaign = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingCampaign = false;
        });
      }
    }
  }

  Future<void> _checkTermsAcceptance() async {
    // Ensure terms are accepted before showing payment options
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) {
      if (mounted) {
        await SupabaseService.instance.signOut();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const WelcomePage()),
          (route) => false,
        );
      }
      return;
    }

    final memberAccepted = await SupabaseService.instance
        .hasMemberAcceptedTerms(user.id);

    if (!memberAccepted && mounted) {
      // Terms not accepted - redirect to member terms page for acceptance
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MemberTermsPage()),
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verifyingPayment) {
      return Scaffold(
        appBar: BrandedAppBar(
          title: const Text('Complete Your Subscription'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Verifying your payment…\nPlease wait a moment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Complete Your Subscription'),
        automaticallyImplyLeading: false, // Prevent back button
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isPaymentFailed) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Auto-renewal payment failed',
                              style: TextStyle(
                                color: Colors.red.shade900,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please update your payment method and complete payment to reactivate your membership and QR access.',
                        style: TextStyle(color: Colors.red.shade800),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ElevatedButton.icon(
                          onPressed: _openStandardPaymentOption,
                          icon: const Icon(Icons.payment),
                          label: const Text('Update Payment Method'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              Icon(
                Icons.payment,
                color: Theme.of(context).primaryColor,
                size: 80,
              ),
              const SizedBox(height: 24),
              const Text(
                'Complete Your Payment',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                widget.isReactivation
                    ? 'Welcome back! To reactivate your membership, please accept the terms and complete your subscription payment.'
                    : 'To access all features and start using the app, please complete your subscription payment.',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_loadingCampaign)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: CircularProgressIndicator(),
                ),
              if (!_loadingCampaign && _eligibleIntroCampaign != null) ...[
                _buildIntroCampaignCard(),
                const SizedBox(height: 12),
                Text(
                  'Your email qualifies for our special entry offer above. Standard monthly signup isn\'t available for promo invitees.',
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              // Standard R99/month signup - hidden when the member is eligible
              // for an intro campaign promotion (they must use the promo offer above).
              if (!_loadingCampaign && _eligibleIntroCampaign == null)
                ElevatedButton(
                  onPressed: _openStandardPaymentOption,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                  child: const Text('Proceed to Payment'),
                ),
              // Promo Key option - only shown for reactivation, not during initial signup
              if (widget.isReactivation) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    final user = SupabaseService.instance.getCurrentUser();
                    if (user == null) return;
                    showDialog(
                      context: context,
                      builder: (context) => TrustedPartnerKeyDialog(
                        userId: user.id,
                        onSuccess: () {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text('Promo key activated! Welcome to Local Lekker.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          NavigationService().navigateToHomeAfterPayment(this.context);
                        },
                      ),
                    );
                  },
                  icon: const Icon(Icons.vpn_key),
                  label: const Text('Have a Promo Key?'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  // Sign out user
                  await SupabaseService.instance.signOut();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const WelcomePage(),
                    ),
                    (route) => false,
                  );
                },
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroCampaignCard() {
    final campaign = _eligibleIntroCampaign!;
    final promo = Map<String, dynamic>.from(
      campaign['promotion'] as Map,
    );
    final freeMonths = (promo['free_months'] as int?) ?? 0;
    final initialChargeCents = (promo['initial_charge_cents'] as int?) ?? 100;
    final renewalChargeCents = (promo['renewal_charge_cents'] as int?) ?? 9900;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Special Entry Offer Available',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '${promo['name']}: Pay R${(initialChargeCents / 100).toStringAsFixed(2)} now, then get $freeMonths month(s) free. After that, auto-renews at R${(renewalChargeCents / 100).toStringAsFixed(2)}/month.',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final userId = SupabaseService.instance.getCurrentUser()?.id;
                // Use push (not pushReplacement) so the member can return
                // to the plan selection via the AppBar back arrow.
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PaymentOptionsScreen(
                      selectedPlan: 'promotion_intro',
                      planDetails: {
                        'name': promo['name'] ?? 'Intro Campaign',
                        'price': initialChargeCents / 100,
                        'description': 'R1 intro payment',
                        'frequency': 1,
                        'free_months': freeMonths,
                        'promotion_id': promo['id'],
                        'participant_id': campaign['participant_id'],
                        'initial_charge_cents': initialChargeCents,
                        'renewal_charge_cents': renewalChargeCents,
                      },
                      userId: userId,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.sports_tennis),
              label: const Text('Activate Entry Offer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentOptionsScreen extends StatefulWidget {
  final String selectedPlan;
  final Map<String, dynamic> planDetails;
  final String? userId; // Optional user ID for pending payment saving

  const PaymentOptionsScreen({
    super.key,
    required this.selectedPlan,
    required this.planDetails,
    this.userId,
  });

  @override
  State<PaymentOptionsScreen> createState() => _PaymentOptionsScreenState();
}

class _PaymentOptionsScreenState extends State<PaymentOptionsScreen> {
  String? _selectedPaymentMethod;
  // CVV entered for the selected saved card. Held transiently only for the
  // duration of a single charge and cleared immediately after, so every
  // interactive saved-card payment is verified with CVV at the gateway.
  String? _savedCardCvv;
  bool _isProcessing = false;
  List<Map<String, dynamic>> _savedPaymentMethods = [];
  bool _isLoadingSavedMethods = true;

  final List<Map<String, dynamic>> _paymentMethodTypes = [
    {
      'id': 'credit_card',
      'name': 'Credit Card / Visa',
      'icon': Icons.credit_card,
      'description': 'Pay with your credit or debit card',
      'available': true,
    },
  ];

  @override
  void initState() {
    super.initState();
    // CRITICAL: Verify terms acceptance before allowing payment
    _verifyTermsAcceptance();
    // Save pending payment info when screen loads
    _savePendingPayment();
    // Load saved payment methods
    _loadSavedPaymentMethods();
  }

  Future<void> _verifyTermsAcceptance() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) {
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const WelcomePage()),
          (route) => false,
        );
      }
      return;
    }

    // Check if member has accepted terms
    final memberAccepted = await SupabaseService.instance
        .hasMemberAcceptedTerms(user.id);

    if (!memberAccepted && mounted) {
      // Terms not accepted - redirect back to terms page
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You must accept the Terms & Conditions before making a payment.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      await NavigationService().navigateToHomeAfterAuth(context);
    }
  }

  Future<void> _savePendingPayment() async {
    // Use provided userId if available, otherwise get current user
    String? memberId = widget.userId;
    if (memberId == null) {
      final user = SupabaseService.instance.getCurrentUser();
      memberId = user?.id;
    }

    if (memberId != null) {
      await PaymentStatusService().savePendingPayment(
        memberId: memberId,
        selectedPlan: widget.selectedPlan,
        planDetails: widget.planDetails,
      );
      if (kDebugMode) {
        print(
          'PaymentOptionsScreen: Saved pending payment for member $memberId',
        );
      }
    } else {
      if (kDebugMode) {
        print(
          'PaymentOptionsScreen: Could not save pending payment - no member ID available',
        );
      }
    }
  }

  Future<void> _loadSavedPaymentMethods() async {
    try {
      setState(() => _isLoadingSavedMethods = true);

      final user = SupabaseService.instance.getCurrentUser();
      if (user != null) {
        _savedPaymentMethods = await PaystackService().getSavedPaymentMethods(
          user.id,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading saved payment methods: $e');
      }
      _savedPaymentMethods = [];
    } finally {
      if (mounted) {
        setState(() => _isLoadingSavedMethods = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Format price to remove decimal if it's .0
    String priceStr = widget.planDetails['price'].toString();
    if (priceStr.endsWith('.0')) {
      priceStr = priceStr.substring(0, priceStr.length - 2);
    }

    return Scaffold(
      appBar: BrandedAppBar(title: const Text('Payment Options'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Plan Summary Card
            _buildPlanSummaryCard(),
            const SizedBox(height: 24),

            // Payment Methods Section
            const Text(
              'Choose Payment Method',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Saved Payment Methods Section
            if (_isLoadingSavedMethods) ...[
              const Center(child: CircularProgressIndicator()),
            ] else if (_savedPaymentMethods.isNotEmpty) ...[
              const Text(
                'Your Saved Payment Methods',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ..._savedPaymentMethods.map(
                (method) => _buildSavedPaymentMethodCard(method),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
            ],

            // Add New Payment Method Section
            const Text(
              'Add New Payment Method',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Payment Method Options
            ..._paymentMethodTypes.map(
              (method) => _buildPaymentMethodCard(method),
            ),

            const SizedBox(height: 32),

            // Pay Now Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedPaymentMethod != null && !_isProcessing
                    ? () => _showPaymentMethodPopup(_selectedPaymentMethod!)
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Text(
                        'Pay R$priceStr Now',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // Security Notice
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.security, color: Colors.blue.shade600),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your payment is secured with 256-bit SSL encryption. We never store your card details.',
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontSize: 12,
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

  Widget _buildPlanSummaryCard() {
    // Format price to remove decimal if it's .0
    String priceStr = widget.planDetails['price'].toString();
    if (priceStr.endsWith('.0')) {
      priceStr = priceStr.substring(0, priceStr.length - 2);
    }

    final isPromoIntro = widget.selectedPlan == 'promotion_intro';
    final freeMonths = widget.planDetails['free_months'] as int?;
    final renewalChargeCents =
      (widget.planDetails['renewal_charge_cents'] as int?) ?? 9900;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Subscription',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              isPromoIntro ? 'R$priceStr today' : 'R$priceStr/month',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isPromoIntro
                  ? 'Then $freeMonths month(s) free, then R${(renewalChargeCents / 100).toStringAsFixed(2)}/month'
                  : 'Billing: monthly',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodCard(Map<String, dynamic> method) {
    final isSelected = _selectedPaymentMethod == method['id'];
    final isAvailable = method['available'] as bool;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isAvailable ? () => _selectPaymentMethod(method['id']) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                method['icon'],
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : isAvailable
                    ? Colors.grey.shade600
                    : Colors.grey.shade400,
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method['name'],
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isAvailable
                            ? Colors.black
                            : Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      method['description'],
                      style: TextStyle(
                        fontSize: 14,
                        color: isAvailable
                            ? Colors.grey.shade600
                            : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isAvailable)
                Text(
                  'Coming Soon',
                  style: TextStyle(
                    color: Colors.orange.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.grey,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSavedPaymentMethodCard(Map<String, dynamic> method) {
    final isSelected = _selectedPaymentMethod == method['id'];
    final methodId =
        method['id'] ??
        method['authorization_code'] ??
        'method_${method.hashCode}';
    final cardType = method['card_type'] ?? 'Card';
    final last4 = method['last4'] ?? '****';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _selectSavedPaymentMethod(methodId),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                _getCardIcon(cardType),
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Colors.grey.shade600,
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$cardType •••• $last4',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Saved payment method',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getCardIcon(String cardType) {
    switch (cardType.toLowerCase()) {
      case 'visa':
        return Icons.credit_card;
      case 'mastercard':
        return Icons.credit_card;
      case 'amex':
      case 'american express':
        return Icons.credit_card;
      default:
        return Icons.credit_card;
    }
  }

  void _selectPaymentMethod(String methodId) {
    setState(() {
      _selectedPaymentMethod = methodId;
    });

    // Show payment method specific popup
    _showPaymentMethodPopup(methodId);
  }

  void _showPaymentMethodPopup(String methodId) {
    switch (methodId) {
      case 'credit_card':
        _showCreditCardPopup();
        break;
    }
  }

  void _showCreditCardPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Credit Card Payment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.credit_card,
                  color: Theme.of(context).primaryColor,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  'You will be redirected to Paystack\'s secure payment page to complete your credit card payment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Amount: R${widget.planDetails['price']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Plan: ${widget.planDetails['name']}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.security,
                        color: Colors.blue.shade600,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Paystack provides PCI DSS compliant payment processing. Your card details are never stored on our servers.',
                          style: TextStyle(
                            color: Colors.blue.shade800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedPaymentMethod = null;
                });
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _processPayment();
              },
              child: const Text('Continue to Paystack'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _processPayment() async {
    if (kDebugMode) {
      print('_processPayment called with method: $_selectedPaymentMethod');
    }

    if (_selectedPaymentMethod == null) {
      if (kDebugMode) {
        print('No payment method selected, returning');
      }
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (kDebugMode) {
        print('Current user: ${user?.id ?? 'null'}');
      }

      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not authenticated')),
          );
        }
        return;
      }

      // Check if this is a saved payment method
      final isSavedMethod = _savedPaymentMethods.any(
        (method) =>
            method['id'] == _selectedPaymentMethod ||
            method['authorization_code'] == _selectedPaymentMethod,
      );

      // Show processing message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Processing payment with ${_getPaymentMethodName(_selectedPaymentMethod!)}...',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      if (kDebugMode) {
        print('Starting Paystack subscription...');
      }
      // Validate plan details
      if (widget.planDetails['price'] == null ||
          widget.planDetails['frequency'] == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Invalid plan details')));
        }
        return;
      }

      if (user.email == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User email is required for payment')),
          );
        }
        return;
      }

      final isPromoIntro = widget.selectedPlan == 'promotion_intro';
      if (isPromoIntro) {
        await _processIntroCampaignPayment(user, isSavedMethod);
        return;
      }

      // Development mode: immediately activate subscription and navigate home
      if (dotenv.env['PAYSTACK_DEVELOPMENT_MODE'] == 'true') {
        final ok = await SubscriptionService().processManualPayment(
          userId: user.id,
          planType: widget.selectedPlan,
        );
        if (mounted && ok) {
          NavigationService().navigateToHomeAfterPayment(context);
        }
        return;
      }

      // For saved payment methods, use existing authorization
      if (isSavedMethod) {
        if (kDebugMode) {
          print('Using saved payment method for subscription renewal');
        }
        // Find the saved method details
        final savedMethod = _savedPaymentMethods.firstWhere(
          (method) =>
              method['id'] == _selectedPaymentMethod ||
              method['authorization_code'] == _selectedPaymentMethod,
          orElse: () => <String, dynamic>{},
        );

        if (savedMethod.isNotEmpty) {
          final authorizationCode =
              savedMethod['authorization_code'] ?? savedMethod['id'];
          // Use PaystackService to charge the saved card
          final success = await PaystackService().chargeSavedCard(
            authorizationCode: authorizationCode,
            cvv: _savedCardCvv,
            amount: (widget.planDetails['price'] as num).toDouble(),
            userId: user.id,
            userEmail: user.email!,
          );
          _savedCardCvv = null; // Never retain the CVV after the charge attempt

          if (success == 'success') {
            // Payment successful, activate subscription
            final ok = await SubscriptionService().processManualPayment(
              userId: user.id,
              planType: widget.selectedPlan,
            );
            if (mounted && ok) {
              NavigationService().navigateToHomeAfterPayment(context);
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Payment failed. Please try again.'),
                ),
              );
            }
          }
        }
        return;
      }

      // For new payment methods, initialize Paystack subscription
      final result = await PaystackService().initializeSubscription(
        plan: widget.selectedPlan,
        amount: (widget.planDetails['price'] as num).toDouble(),
        frequency: (widget.planDetails['frequency'] as num).toInt(),
        userId: user.id,
        userEmail: user.email!,
      );

      if (result == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to initialize payment. Please try again.'),
            ),
          );
        }
        return;
      }

      final authUrl = result['authorization_url']!;
      final transactionReference = result['reference']!;

      if (kDebugMode) {
        print(
          'Paystack subscription initiated with reference: $transactionReference, showing payment screen...',
        );
      }

      // Save transaction reference for recovery if app closes during payment
      await PaymentStatusService().savePendingTransactionReference(
        userId: user.id,
        reference: transactionReference,
        planType: widget.selectedPlan,
      );

      // webview_flutter's in-app WebView is unsupported on web (throws at
      // controller creation, leaving a blank/grey screen). Navigate this tab to
      // the Paystack checkout instead; the server-side paystack-webhook
      // activates the subscription before Paystack redirects back to the app.
      if (kIsWeb) {
        final opened = await openWebCheckout(authUrl);
        if (!opened) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Could not open the secure payment page. Please try again.',
                ),
              ),
            );
          }
          return;
        }
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentPendingScreen(
                planName: widget.selectedPlan,
                amount: (widget.planDetails['price'] as num).toDouble(),
                userId: user.id,
              ),
            ),
          );
        }
        return;
      }

      // Open inline webview for Paystack checkout
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaystackWebViewPage(
              authorizationUrl: authUrl,
              userId: user.id,
              planType: widget.selectedPlan,
              transactionReference: transactionReference,
            ),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Payment processing failed: $e');
      }
      if (mounted) {
        // Show user-friendly error messages
        String errorMessage = e.toString().replaceAll('Exception: ', '');
        if (errorMessage.contains('invalid_api_key')) {
          errorMessage = 'Payment service temporarily unavailable. Please try again later or contact support.';
        } else if (errorMessage.contains('network_error') ||
                   errorMessage.contains('connection abort') ||
                   errorMessage.contains('Connection failed') ||
                   errorMessage.contains('SocketException') ||
                   errorMessage.contains('ClientException') ||
                   errorMessage.contains('TimeoutException')) {
          errorMessage = 'Connection failed. Please check your internet connection and try again.';
        } else if (errorMessage.contains('auth_error')) {
          errorMessage = 'Your session has expired. Please sign in again and retry the payment.';
        } else if (errorMessage.contains('server_error')) {
          // Surface the upstream Paystack / Edge Function detail so the issue
          // is actionable (e.g. missing plan code, invalid customer, etc.)
          final idx = errorMessage.indexOf('server_error');
          final detail = errorMessage.substring(idx).replaceFirst(
            RegExp(r'^server_error\s*\(\d+\)\s*-\s*'),
            '',
          );
          errorMessage = 'Payment could not be started: $detail';
        } else if (errorMessage.contains('No Paystack plan code configured')) {
          errorMessage = 'Payment plan is not configured. Please contact support.';
        } else if (errorMessage.contains('Failed to initialize subscription')) {
          // Generic fallback — avoid blaming the user's connection when we
          // don't actually know it's a network problem.
          errorMessage = 'Could not start payment. Please try again or contact support.';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
      if (kDebugMode) {
        print('Payment processing completed');
      }
    }
  }

  Future<void> _processIntroCampaignPayment(
    User user,
    bool isSavedMethod,
  ) async {
    final initialCharge = (widget.planDetails['price'] as num).toDouble();
    final freeMonths = (widget.planDetails['free_months'] as int?) ?? 0;
    final promotionId = widget.planDetails['promotion_id'] as String?;
    final participantId = widget.planDetails['participant_id'] as String?;
    final initialChargeCents =
        (widget.planDetails['initial_charge_cents'] as int?) ?? 100;
    final renewalChargeCents =
        (widget.planDetails['renewal_charge_cents'] as int?) ?? 9900;

    if (promotionId == null || participantId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offer metadata missing. Please try again.')),
        );
      }
      return;
    }

    if (dotenv.env['PAYSTACK_DEVELOPMENT_MODE'] == 'true') {
      final ok = await SubscriptionService().activateIntroCampaignSubscription(
        userId: user.id,
        promotionId: promotionId,
        participantId: participantId,
        freeMonths: freeMonths,
        initialChargeCents: initialChargeCents,
        renewalChargeCents: renewalChargeCents,
      );
      if (mounted && ok) {
        await NavigationService().navigateToHomeAfterPayment(context);
      }
      return;
    }

    if (isSavedMethod) {
      final savedMethod = _savedPaymentMethods.firstWhere(
        (method) =>
            method['id'] == _selectedPaymentMethod ||
            method['authorization_code'] == _selectedPaymentMethod,
        orElse: () => <String, dynamic>{},
      );

      if (savedMethod.isEmpty) return;

      final authorizationCode =
          savedMethod['authorization_code'] ?? savedMethod['id'];
      final paymentResult = await PaystackService().chargeSavedCard(
        authorizationCode: authorizationCode,
        cvv: _savedCardCvv,
        amount: initialCharge,
        userId: user.id,
        userEmail: user.email!,
        paymentType: 'promotion_intro',
        extraMetadata: {
          'promotion_id': promotionId,
          'participant_id': participantId,
          'free_months': freeMonths,
          'initial_charge_cents': initialChargeCents,
          'renewal_charge_cents': renewalChargeCents,
        },
      );
      _savedCardCvv = null; // Never retain the CVV after the charge attempt

      if (paymentResult == 'success') {
        final ok = await SubscriptionService().activateIntroCampaignSubscription(
          userId: user.id,
          promotionId: promotionId,
          participantId: participantId,
          freeMonths: freeMonths,
          initialChargeCents: initialChargeCents,
          renewalChargeCents: renewalChargeCents,
        );

        if (mounted && ok) {
          await NavigationService().navigateToHomeAfterPayment(context);
        }
      }
      return;
    }

    final result = await PaystackService().startOneTimePayment(
      itemName: widget.planDetails['name']?.toString() ?? 'Intro Campaign',
      itemDescription:
          'Intro charge R${initialCharge.toStringAsFixed(2)} with $freeMonths month(s) free',
      amount: initialCharge,
      userId: user.id,
      userEmail: user.email!,
      extraMetadata: {
        'payment_type': 'promotion_intro',
        'promotion_id': promotionId,
        'participant_id': participantId,
        'free_months': freeMonths,
        'initial_charge_cents': initialChargeCents,
        'renewal_charge_cents': renewalChargeCents,
      },
    );

    if (result == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to initialize payment. Please try again.')),
        );
      }
      return;
    }

    final authUrl = result['authorization_url']!;
    final transactionReference = result['reference']!;

    await PaymentStatusService().savePendingTransactionReference(
      userId: user.id,
      reference: transactionReference,
      planType: widget.selectedPlan,
    );

    // webview_flutter's in-app WebView is unsupported on web (throws at
    // controller creation, leaving a blank/grey screen). Navigate this tab to
    // the Paystack checkout instead; the server-side paystack-webhook activates
    // the intro subscription before Paystack redirects back to the app.
    if (kIsWeb) {
      final opened = await openWebCheckout(authUrl);
      if (!opened) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not open the secure payment page. Please try again.',
              ),
            ),
          );
        }
        return;
      }
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentPendingScreen(
              planName: widget.selectedPlan,
              amount: initialCharge,
              userId: user.id,
            ),
          ),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaystackWebViewPage(
            authorizationUrl: authUrl,
            userId: user.id,
            planType: widget.selectedPlan,
            transactionReference: transactionReference,
            promoContext: {
              'promotion_id': promotionId,
              'participant_id': participantId,
              'free_months': freeMonths,
              'initial_charge_cents': initialChargeCents,
              'renewal_charge_cents': renewalChargeCents,
            },
          ),
        ),
      );
    }
  }

  String _getPaymentMethodName(String methodId) {
    switch (methodId) {
      case 'credit_card':
        return 'Credit Card';
      default:
        return 'Selected Method';
    }
  }

  void _selectSavedPaymentMethod(String methodId) {
    setState(() {
      _selectedPaymentMethod = methodId;
    });
    // For saved payment methods, prompt for CVV before processing
    _showSavedCardCvvDialog(methodId);
  }

  /// Shows a dialog requiring the member to enter their CVV before charging a saved card.
  /// The CVV field is always empty — never pre-filled.
  void _showSavedCardCvvDialog(String methodId) {
    final savedMethod = _savedPaymentMethods.firstWhere(
      (method) =>
          method['id'] == methodId ||
          method['authorization_code'] == methodId,
      orElse: () => <String, dynamic>{},
    );

    if (savedMethod.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved card not found.')),
      );
      return;
    }

    final cardType = savedMethod['card_type'] ?? 'Card';
    final last4 = savedMethod['last4'] ?? '****';
    final cvvController = TextEditingController(); // Always starts empty
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Enter CVV'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      _getCardIcon(cardType),
                      color: Theme.of(context).primaryColor,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$cardType •••• $last4',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'For your security, please enter the CVV from the back of your card.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: cvvController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'CVV',
                    hintText: 'Enter CVV',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    counterText: '',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'CVV is required';
                    }
                    if (!RegExp(r'^\d{3,4}$').hasMatch(value)) {
                      return 'Enter a valid 3 or 4 digit CVV';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedPaymentMethod = null;
                  _savedCardCvv = null;
                });
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  // Capture the CVV so it is passed to the gateway charge.
                  _savedCardCvv = cvvController.text.trim();
                  Navigator.of(dialogContext).pop();
                  _processPayment();
                }
              },
              child: const Text('Pay Now'),
            ),
          ],
        );
      },
    );
  }
}

class PaymentPendingScreen extends StatefulWidget {
  final String planName;
  final double amount;
  final String userId;

  const PaymentPendingScreen({
    super.key,
    required this.planName,
    required this.amount,
    required this.userId,
  });

  @override
  State<PaymentPendingScreen> createState() => _PaymentPendingScreenState();
}

class _PaymentPendingScreenState extends State<PaymentPendingScreen> {
  bool _isCheckingPayment = false;
  StreamSubscription<String?>? _deepLinkSubscription;

  @override
  void initState() {
    super.initState();
    // Listen for deep link callbacks
    _deepLinkSubscription = DeepLinkService().linkStream.listen((link) {
      if (link != null && link.startsWith('payment_callback:')) {
        if (kDebugMode) {
          print(
            'PaymentPendingScreen: Received payment callback, checking status',
          );
        }
        _checkPaymentStatus();
      }
    });
    // Start checking for payment status
    _checkPaymentStatus();
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkPaymentStatus() async {
    setState(() {
      _isCheckingPayment = true;
    });

    try {
      // Check subscription status
      final subscriptionService = SubscriptionService();
      final status = await subscriptionService.getSubscriptionStatus(
        widget.userId,
      );

      if (status != null &&
          status['subscription_status'] == 'active' &&
          status['has_active_qr'] == true) {
        // Payment completed successfully, navigate to home
        if (mounted) {
          NavigationService().navigateToHomeAfterPayment(context);
        }
      } else {
        // Payment still pending, check again in 3 seconds
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) {
          _checkPaymentStatus();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error checking payment status: $e');
      }
      // Continue checking
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        _checkPaymentStatus();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingPayment = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Processing Payment'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              const Text(
                'Processing Your Payment',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Please complete your payment on Paystack. We\'re waiting for confirmation...\n\nPlan: ${widget.planName}\nAmount: R${widget.amount.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_isCheckingPayment)
                const Text(
                  'Checking payment status...',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Manually check payment status
                  _checkPaymentStatus();
                },
                child: const Text('Check Payment Status'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
