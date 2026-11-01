import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/supabase_service.dart';
import '../../services/navigation_service.dart';

class MemberTermsPage extends StatefulWidget {
  /// When true the page pops with `true` on acceptance (and allows backing
  /// out with `null`) instead of routing through the post-auth navigation.
  /// Used when terms are collected inline right before a subscription payment.
  final bool popOnAccept;

  const MemberTermsPage({super.key, this.popOnAccept = false});

  @override
  State<MemberTermsPage> createState() => _MemberTermsPageState();
}

class _MemberTermsPageState extends State<MemberTermsPage> {
  bool _checked = false;
  bool _submitting = false;
  String? _error;
  static const String _termsVersion = 'v2025-11-10';

  Future<void> _accept() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) {
      setState(() => _error = 'Not authenticated.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final ok = await SupabaseService.instance.acceptMemberTerms(
        userId: user.id,
        version: _termsVersion,
      );
      if (!mounted) return;
      if (ok) {
        if (widget.popOnAccept) {
          Navigator.of(context).pop(true);
          return;
        }
        // Use centralized navigation so we only show payment screen if subscription truly pending
        await NavigationService().navigateToHomeAfterAuth(context);
      } else {
        setState(() => _error = 'Failed to save acceptance. Try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Member Terms & Conditions'),
        automaticallyImplyLeading: widget.popOnAccept,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Scrollbar(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'LOCAL LEKKER CLUB – MEMBER TERMS & CONDITIONS',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          '1. Introduction\n\nThese Terms and Conditions ("Terms") govern the use of the Local Lekker Club App ("the App") operated by Inoven Pty Ltd t/a Local Lekker Club ("the Company", "we", "our", or "us").\nBy downloading, registering, or using the App, you ("the Member", "you", or "your") agree to these Terms in full. If you do not agree, you must not use the App.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '2. Membership and Subscription\n\n2.1. Membership grants access to exclusive deals, discounts, and promotions offered by our approved Trusted Partners.\n2.2. Membership is billed at R99 per month, payable in advance via the secure payment gateway linked in the App.\n2.3. Payments are processed on a recurring monthly basis until cancelled by the Member.\n2.4. Members may cancel their subscription at any time through the App or in writing to the Company at least 7 days before the next billing date.\n2.5. Cancellation will not result in a refund of any portion of a monthly fee already paid. Access remains active until the end of the paid period.\n2.6. The Company reserves the right to adjust subscription fees with 30 days’ prior notice. Updated fees apply after the next billing cycle.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '3. Use of the App\n\n3.1. The App and its content are provided for personal use only.\n3.2. You may not reproduce, copy, distribute, or use any material from the App for commercial purposes.\n3.3. You agree to use the App lawfully and not in any way that could damage or impair it.\n3.4. You may not share screenshots or recordings of membership pages, QR codes, or offers, nor attempt to grant access to non-members.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '4. Member Benefits\n\n4.1. Only active Members may redeem offers listed in the App.\n4.2. All offers and discounts are provided by Trusted Partners, not by the Company.\n4.3. Each Partner is responsible for accuracy and fulfilment of offers.\n4.4. Offers may change or expire without notice.\n4.5. Offers may not be combined with other promotions unless allowed by the Partner.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '5. POPI ACT COMPLIANCE\n\n5.1. We comply with the POPI Act.\n5.2. By registering you consent to collection and processing of personal info for membership management, identity verification, communication and app improvement.\n5.3. Personal info is not sold or shared except where required by law or necessary for services (e.g., payment processors).\n5.4. You may request access, correction or deletion via info@locallekkerclub.co.za.\n5.5. We apply appropriate security safeguards.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '6. Payment Processing\n\n6.1. Payments are handled by secure third-party processors (e.g., Paystack).\n6.2. We do not store full card details.\n6.3. Failed payments may suspend membership until resolved.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '7. Limitation of Liability\n\n7.1. The App is provided “as is” without warranties.\n7.2. We are not liable for offer inaccuracies, Partner non-compliance, or damages arising from App use.\n7.3. Our total liability, if any, is limited to the amount you paid in the previous three months.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '8. Intellectual Property\n\nAll trademarks, logos and designs remain our property. No reproduction without permission.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '9. Termination of Membership\n\n9.1. We may suspend or terminate access for fraud, breach, or reputational risk.\n9.2. Termination does not grant refund of paid period.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '10. App Updates and Availability\n\n10.1. Features may change without notice.\n10.2. We aim for uptime but do not guarantee uninterrupted availability.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '11. Dispute Resolution\n\n11.1. Disputes should first be handled amicably.\n11.2. Failing resolution, South African law applies; East London Magistrates’ Court jurisdiction.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '12. Changes to These Terms\n\nContinued use after updates constitutes acceptance of revised Terms.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '13. Contact Information\n\nInoven Pty Ltd t/a Local Lekker Club\nEmail: info@locallekkerclub.co.za\nWebsite: www.locallekkerclub.co.za\nAddress: East London, Eastern Cape, South Africa',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!, style: TextStyle(color: cs.error)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _checked,
                        onChanged: _submitting
                            ? null
                            : (v) => setState(() => _checked = v ?? false),
                      ),
                      const Expanded(
                        child: Text(
                          'I have read and agree to the Member Terms & Conditions.',
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _checked && !_submitting ? _accept : null,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Accept & Proceed to Payment'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Terms version: $_termsVersion',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
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
