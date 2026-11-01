import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/supabase_service.dart';
import '../../services/navigation_service.dart';

/// Terms & Conditions page for Trusted Partners.
/// Must be accepted once before accessing the Trusted Partner home.
class TrustedPartnerTermsPage extends StatefulWidget {
  const TrustedPartnerTermsPage({super.key});

  @override
  State<TrustedPartnerTermsPage> createState() =>
      _TrustedPartnerTermsPageState();
}

class _TrustedPartnerTermsPageState extends State<TrustedPartnerTermsPage> {
  bool _ackChecked = false;
  bool _submitting = false;
  String? _error;

  static const String _termsVersion = 'v2025-11-10';

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
      final ok = await SupabaseService.instance.acceptTrustedPartnerTerms(
        userId: user.id,
        version: _termsVersion,
      );
      if (!mounted) return;
      if (ok) {
        // Route to the correct next screen using centralized navigation
        if (!mounted) return;
        await NavigationService().navigateToHomeAfterAuth(context);
      } else {
        setState(
          () => _error = 'Could not save your acceptance. Please try again.',
        );
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
        title: const Text('Trusted Partner Agreement'),
        automaticallyImplyLeading: false, // enforce acceptance before leaving
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
                          'LOCAL LEKKER CLUB – TRUSTED PARTNER AGREEMENT AND TERMS & CONDITIONS',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          '1. Parties\n\nThis Agreement is entered into between:\nInoven Pty Ltd t/a Local Lekker Club ("the Company") and The Registered Business Partner ("the Partner"), collectively referred to as "the Parties".\n\nBy downloading, accessing, or using the Local Lekker Club App, the Partner acknowledges and agrees to the terms below.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '2. Purpose\n\nThe purpose of this Agreement is to formalize the participation of the Partner as a Trusted Partner of the Local Lekker Club. The Partner agrees to offer exclusive discounts, deals, or benefits ("Offers") to registered Local Lekker Club Members through the Local Lekker App.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '3. Trusted Partner Obligations\n\n3.1. The Partner confirms that all Offers listed on the App are exclusive to Local Lekker Club Members and not made available to the general public through any other platform, unless expressly approved in writing by the Company.\n3.2. The Partner agrees to update or refresh Offers at least every 60 (sixty) days to ensure relevance and variety. Offers may be updated more frequently but may not remain unchanged indefinitely, unless otherwise approved in writing by the Company.\n3.3. The Partner must ensure that all advertised discounts or offers are honoured in-store or online as stated on the App.\n3.4. The Partner remains responsible for ensuring that all descriptions, prices, and terms of their Offers are accurate and not misleading.\n3.5. The Partner agrees to promptly notify the Company of any changes to business details, contact information, or the nature of offers.\n3.6. The Partner authorizes the Company to use their business name, logo, images, and offer details for marketing and promotional purposes across Local Lekker Club’s platforms (including website, app, social media, and print).',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '4. Company Obligations\n\n4.1. The Company will promote the Partner as an official Trusted Partner of the Local Lekker Club across its platforms.\n4.2. The Company will ensure that only registered Local Lekker Club Members can access and redeem the Partner’s Offers.\n4.3. The Company will manage the App, updates, and any technical integrations necessary for the Offers to be visible to Members.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '5. Term and Termination\n\n5.1. This Agreement commences on the date the Partner accepts these Terms via the App and remains valid until terminated by either Party.\n5.2. Either Party may terminate this Agreement with 30 (thirty) days’ written notice.\n5.3. The Company reserves the right to suspend or remove a Partner from the App immediately if: (a) The Partner fails to honour offers or misleads Members. (b) The Partner’s business conduct harms or may harm the reputation of the Local Lekker Club. (c) The Partner violates any clause of this Agreement.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '6. Fees\n\nUnless otherwise agreed in writing, no participation fee or commission is payable by the Partner to the Company for listing Offers on the App.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '7. Intellectual Property\n\nAll content, software, design, and data associated with the Local Lekker Club App remain the sole property of the Company. The Partner may not copy, modify, or distribute any material from the App without written consent.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '8. POPI ACT COMPLIANCE (Protection of Personal Information Act, No. 4 of 2013)\n\n8.1. Both Parties agree to comply fully with the POPI Act in relation to the processing of personal information.\n8.2. The Company undertakes to collect, store, and process personal data of Members and Partners only for legitimate business purposes related to the Local Lekker Club.\n8.3. Personal information will not be sold, shared, or disclosed to third parties without consent, except where required by law.\n8.4. The Partner agrees to handle any personal information received from the Company (such as Member verification or redemption data) in strict confidence and in compliance with the POPI Act.\n8.5. Partners must not use Member information for unrelated marketing or data collection purposes without explicit consent from the Member and the Company.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '9. Indemnity and Limitation of Liability\n\n9.1. The Partner indemnifies the Company against any claims, damages, or losses arising from: (a) Inaccurate or misleading offers; (b) Failure to honour an offer; or (c) Negligent or unlawful conduct by the Partner.\n9.2. The Company is not liable for any loss of revenue, goodwill, or data resulting from the use of the App.\n9.3. The App and related services are provided “as is” without warranties of any kind, express or implied.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '10. Confidentiality\n\nBoth Parties agree to keep all non-public information (including pricing, business data, and marketing strategies) confidential and not disclose it without prior written consent.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '11. Governing Law\n\nThis Agreement shall be governed by and construed in accordance with the laws of the Republic of South Africa. Any disputes arising shall be subject to the jurisdiction of the East London Magistrates’ Court, unless otherwise agreed.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          '12. Acceptance\n\nBy downloading, accessing, or using the Local Lekker Club App, the Partner acknowledges that they have read, understood, and agreed to the terms set out in this Trusted Partner Agreement and Terms & Conditions.',
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
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _ackChecked,
                        onChanged: _submitting
                            ? null
                            : (v) => setState(() => _ackChecked = v ?? false),
                      ),
                      const Expanded(
                        child: Text(
                          'I have read and agree to the terms above.',
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _ackChecked && !_submitting ? _accept : null,
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
}
