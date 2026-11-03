import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

class GuestSignInBanner extends StatelessWidget {
  final VoidCallback onSignIn;
  final VoidCallback onDismiss;

  const GuestSignInBanner({
    super.key,
    required this.onSignIn,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Browse deals and see what you could save',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Close sign-in banner',
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Text(
              'An active membership is required to request deals. Sign up or '
              'sign in when you are ready to start saving.',
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: onSignIn,
              child: const Text('Sign up or sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
