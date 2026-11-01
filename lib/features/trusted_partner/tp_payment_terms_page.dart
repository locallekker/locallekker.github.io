import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/supabase_service.dart';

/// Payment Gateway Terms & Conditions page for Trusted Partners.
/// Must be accepted before the TP can load banking details.
class TpPaymentTermsPage extends StatefulWidget {
  /// Called when the TP accepts the terms.
  final VoidCallback onAccepted;

  const TpPaymentTermsPage({super.key, required this.onAccepted});

  @override
  State<TpPaymentTermsPage> createState() => _TpPaymentTermsPageState();
}

class _TpPaymentTermsPageState extends State<TpPaymentTermsPage> {
  bool _checked = false;
  bool _submitting = false;
  String? _error;

  static const String _termsVersion = 'v2026-04-13';

  Future<void> _accept() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) {
      setState(() => _error = 'Not signed in.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final ok = await SupabaseService.instance.acceptTpPaymentTerms(
        userId: user.id,
        version: _termsVersion,
      );
      if (!mounted) return;
      if (!ok) {
        setState(() => _error = 'Could not save your acceptance. Please try again.');
        return;
      }
      widget.onAccepted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Payment Terms'),
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
                      children: [
                        const Text(
                          'Payment Gateway, Sub-Account Allocation, Fees and Limitation of Liability',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Local Lekker Club utilises Paystack as its designated third-party payment gateway for the processing, allocation and settlement of all Partner-related transactions.',
                        ),
                        const SizedBox(height: 16),

                        // Consent section
                        const Text(
                          'By providing your banking details, you acknowledge, consent and agree that:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildBullet(
                          'Your banking details will be securely processed and stored by Paystack in accordance with its security, compliance and POPIA requirements.',
                        ),
                        _buildBullet(
                          'A Paystack sub-account will be created and maintained under the Local Lekker Club master Paystack profile in your registered business name.',
                        ),
                        _buildBullet(
                          'This sub-account enables the automated allocation and settlement of funds due to you from transactions processed via the Local Lekker Club platform.',
                        ),
                        const SizedBox(height: 20),

                        // Transaction Fees
                        const Text(
                          'Transaction Fees',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'All transactions processed through Paystack are subject to Paystack\'s prevailing fee structure, currently:',
                        ),
                        const SizedBox(height: 8),
                        _buildBullet(
                          '2.9% + R1.00 per successful transaction for South African cards, capped at R30.00 per transaction',
                        ),
                        _buildBullet(
                          '3.9% + R1.00 per successful transaction for international cards',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'All applicable fees are deducted automatically by Paystack prior to settlement. Paystack reserves the right to amend its fees at any time, and such changes will apply immediately without requiring further consent from Local Lekker Club or the Trusted Partner.',
                        ),
                        const SizedBox(height: 20),

                        // Settlement Timeframes
                        const Text(
                          'Settlement Timeframes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Settlement of funds to your nominated bank account typically occurs within 2 to 3 business days (T+2 to T+3), excluding weekends and public holidays.',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Settlement timelines are dependent on Paystack\'s systems, banking processes, and may be affected by compliance checks, verification procedures, disputes, or delays within the banking network.',
                        ),
                        const SizedBox(height: 20),

                        // Acceptance and Authority
                        const Text(
                          'Acceptance and Authority',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'By submitting your banking details, you:',
                        ),
                        const SizedBox(height: 8),
                        _buildBullet(
                          'Confirm acceptance of Paystack\'s terms and conditions and fee structure',
                        ),
                        _buildBullet(
                          'Authorise Local Lekker Club to create, link and manage your Paystack sub-account for payment processing purposes',
                        ),
                        _buildBullet(
                          'Acknowledge that all funds flow through Paystack and are subject to its systems, controls and processes',
                        ),
                        const SizedBox(height: 20),

                        // Limitation of Liability
                        const Text(
                          'Limitation of Liability',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildBullet(
                          'Local Lekker Club acts solely as an intermediary facilitating payment processing via Paystack and does not hold or control Partner funds.',
                        ),
                        _buildBullet(
                          'Local Lekker Club shall not be liable for any delays, failed payments, incorrect settlements, chargebacks, reversals, or losses arising from or related to Paystack\'s systems, banking institutions, or third-party processing.',
                        ),
                        _buildBullet(
                          'Local Lekker Club shall not be held responsible for any changes to Paystack\'s fees, policies, or settlement timelines.',
                        ),
                        _buildBullet(
                          'The Trusted Partner agrees to indemnify and hold Local Lekker Club harmless against any claims, losses, damages, or disputes arising from the use of Paystack as a payment gateway.',
                        ),
                        const SizedBox(height: 24),

                        // Paystack links
                        const Text(
                          'More Information',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _openLink('https://paystack.com/terms'),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.open_in_new, size: 18, color: Colors.blue),
                                SizedBox(width: 8),
                                Text(
                                  'Paystack Terms & Conditions',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _openLink('https://paystack.com/pricing'),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.open_in_new, size: 18, color: Colors.blue),
                                SizedBox(width: 8),
                                Text(
                                  'Paystack Transaction Pricing',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Error message
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  _error!,
                  style: TextStyle(color: cs.error),
                ),
              ),

            // Checkbox + Accept button
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
                          'I have read, understand and agree to the payment terms above.',
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
                          : const Text('Accept & Continue'),
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

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 14)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
