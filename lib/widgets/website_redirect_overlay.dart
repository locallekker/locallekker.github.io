import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/website_redirect_service.dart';
import '../services/admin_engagement_service.dart';

const Duration _kRedirectDelay = Duration(milliseconds: 1500);

/// Shows the "Redirecting..." message, then opens the partner's website.
Future<void> openWebsiteRedirectDeal(
  BuildContext context, {
  required String dealId,
  required String partnerName,
  String? trustedPartnerId,
  String? websiteUrl,
  String? logoUrl,
}) {
  return _openRedirectDeal(
    context,
    dealId: dealId,
    partnerName: partnerName,
    trustedPartnerId: trustedPartnerId,
    url: websiteUrl,
    logoUrl: logoUrl,
    unavailableMessage: "$partnerName's website isn't available right now.",
    redirectingMessage: "Redirecting to $partnerName's homepage...",
    failureMessage: "Could not open $partnerName's website.",
  );
}

/// Shows the "Redirecting..." message, then opens the partner's booking page.
Future<void> openBookingRedirectDeal(
  BuildContext context, {
  required String dealId,
  required String partnerName,
  String? trustedPartnerId,
  String? bookingUrl,
  String? logoUrl,
}) {
  return _openRedirectDeal(
    context,
    dealId: dealId,
    partnerName: partnerName,
    trustedPartnerId: trustedPartnerId,
    url: bookingUrl,
    logoUrl: logoUrl,
    unavailableMessage: "$partnerName's booking page isn't available right now.",
    redirectingMessage: "Redirecting to $partnerName's booking page...",
    failureMessage: "Could not open $partnerName's booking page.",
  );
}

Future<void> _openRedirectDeal(
  BuildContext context, {
  required String dealId,
  required String partnerName,
  required String redirectingMessage,
  required String unavailableMessage,
  required String failureMessage,
  String? trustedPartnerId,
  String? url,
  String? logoUrl,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final service = WebsiteRedirectService();
  unawaited(AdminEngagementService().recordDealOpen(dealId));

  final uri = WebsiteRedirectService.normalizeWebsiteUrl(url);
  if (uri == null) {
    messenger.showSnackBar(SnackBar(content: Text(unavailableMessage)));
    return;
  }

  unawaited(
    service.logClick(dealId: dealId, trustedPartnerId: trustedPartnerId),
  );

  // Browsers block pop-ups opened after a delay, so web launches immediately.
  final Future<bool>? webLaunch = kIsWeb ? service.launch(uri) : null;

  var dialogOpen = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => _RedirectingDialog(
        message: redirectingMessage,
        logoUrl: logoUrl,
      ),
    ).whenComplete(() => dialogOpen = false),
  );

  await Future<void>.delayed(_kRedirectDelay);
  final launched = await (webLaunch ?? service.launch(uri));

  if (dialogOpen && navigator.mounted) navigator.pop();

  if (!launched) {
    messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
  }
}

class _RedirectingDialog extends StatelessWidget {
  final String message;
  final String? logoUrl;

  const _RedirectingDialog({required this.message, this.logoUrl});

  static const Color _brandGreen = Color(0xFF3C8C44);
  static const Color _brandBlue = Color(0xFF0E5BA0);

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoUrl != null && logoUrl!.isNotEmpty;
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: hasLogo
                    ? Image.network(
                        logoUrl!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _FallbackLogo(),
                      )
                    : const _FallbackLogo(),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: _brandGreen,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _brandBlue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap back to return to Local Lekker.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      color: const Color(0xFF0E5BA0).withValues(alpha: 0.12),
      child: const Icon(Icons.language, size: 32, color: Color(0xFF0E5BA0)),
    );
  }
}
