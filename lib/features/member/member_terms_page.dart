import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/supabase_service.dart';
import '../../services/navigation_service.dart';
import 'member_terms_content.dart';

class MemberTermsPage extends StatefulWidget {
  final bool readOnly;

  const MemberTermsPage({super.key, this.readOnly = false});

  @override
  State<MemberTermsPage> createState() => _MemberTermsPageState();
}

class _MemberTermsPageState extends State<MemberTermsPage> {
  bool _checked = false;
  bool _submitting = false;
  String? _error;
  static const String _termsVersion = MemberTermsContent.termsVersion;

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
        // Use centralized navigation so we only show payment screen if subscription truly pending
        if (!mounted) return;
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
        automaticallyImplyLeading: widget.readOnly,
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
                      children: const [Text(MemberTermsContent.text)],
                    ),
                  ),
                ),
              ),
            ),
            if (!widget.readOnly && _error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!, style: TextStyle(color: cs.error)),
              ),
            if (!widget.readOnly)
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Accept & Proceed to Payment'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Terms version: $_termsVersion',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
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
