import 'package:flutter/material.dart';

import '../core/constants/deal_categories.dart';
import '../services/supabase_service.dart';

/// Non-blocking notice shown on the deal form when a partner selects the
/// Local Sips category without a verified liquor licence on file.
class LiquorLicenceWarning extends StatefulWidget {
  final String selectedCategory;

  const LiquorLicenceWarning({super.key, required this.selectedCategory});

  @override
  State<LiquorLicenceWarning> createState() => _LiquorLicenceWarningState();
}

class _LiquorLicenceWarningState extends State<LiquorLicenceWarning> {
  bool? _verified;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return;
    try {
      final row = await SupabaseService.instance.client
          .from('businesses')
          .select('liquor_license_verified')
          .eq('owner_member_id', user.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _verified = row?['liquor_license_verified'] == true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _verified = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedCategory != kLocalSipsCategory) {
      return const SizedBox.shrink();
    }
    if (_verified != false) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0B65C)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFF8A5A00)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your liquor licence has not been verified by Local Lekker yet. '
              'This deal will still publish, but it may be removed until your '
              'national liquor and distribution licence documents are on file.',
              style: TextStyle(fontSize: 12, color: Color(0xFF8A5A00)),
            ),
          ),
        ],
      ),
    );
  }
}
