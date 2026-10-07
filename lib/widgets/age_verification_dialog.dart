import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../services/supabase_service.dart';

const Color _wineDark = Color(0xFF722F37);

/// 18+ self-confirmation gate for the Local Sips section.
///
/// Returns true when the member has confirmed (now or previously). The result
/// is stored on the profile, so a confirmed member is never asked again.
Future<bool> ensureMemberIsAgeVerified(BuildContext context) async {
  final user = SupabaseService.instance.getCurrentUser();
  if (user == null) return false;

  if (await SupabaseService.instance.isMemberAgeVerified(user.id)) return true;
  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _AgeVerificationDialog(),
  );
  return confirmed ?? false;
}

class _AgeVerificationDialog extends StatefulWidget {
  const _AgeVerificationDialog();

  @override
  State<_AgeVerificationDialog> createState() => _AgeVerificationDialogState();
}

class _AgeVerificationDialogState extends State<_AgeVerificationDialog> {
  bool _checked = false;
  bool _submitting = false;
  String? _error;

  Future<void> _confirm() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) {
      setState(() => _error = 'You need to be signed in to continue.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final ok = await SupabaseService.instance.confirmMemberAge18(user.id);
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _submitting = false;
        _error = 'Could not save your confirmation. Please try again.';
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _wineDark.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.wine_bar, color: _wineDark),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Age restricted',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Local Sips features locally produced wines, beers and spirits. '
            'South African law prohibits the sale or supply of alcohol to '
            'anyone under the age of 18.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: _wineDark,
            value: _checked,
            onChanged: _submitting
                ? null
                : (value) => setState(() => _checked = value ?? false),
            title: const Text(
              'I confirm that I am 18 years or older',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Drink responsibly. Not for sale to persons under the age of 18.',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _wineDark,
            foregroundColor: Colors.white,
          ),
          onPressed: (_checked && !_submitting) ? _confirm : null,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Continue'),
        ),
      ],
    );
  }
}
