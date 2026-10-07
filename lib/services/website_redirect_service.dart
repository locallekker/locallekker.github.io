import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';

import 'supabase_service.dart';

/// Opens partner websites for website-redirect deals and records clicks.
class WebsiteRedirectService {
  static final WebsiteRedirectService _instance =
      WebsiteRedirectService._internal();
  factory WebsiteRedirectService() => _instance;
  WebsiteRedirectService._internal();

  final Logger _logger = Logger();

  static final RegExp _hostPattern = RegExp(
    r'^([a-z0-9-]+\.)+[a-z]{2,}$',
    caseSensitive: false,
  );

  /// Returns a safe https URI for a stored website value, or null if invalid.
  static Uri? normalizeWebsiteUrl(String? raw) {
    var value = raw?.trim() ?? '';
    if (value.isEmpty) return null;

    final lower = value.toLowerCase();
    if (lower.startsWith('http://')) {
      value = 'https://${value.substring(7)}';
    } else if (!lower.startsWith('https://')) {
      value = 'https://$value';
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        !_hostPattern.hasMatch(uri.host)) {
      return null;
    }
    return uri;
  }

  Future<void> logClick({
    required String dealId,
    String? trustedPartnerId,
  }) async {
    final userId = SupabaseService.instance.getCurrentUser()?.id;
    if (userId == null) return;
    try {
      await SupabaseService.instance.client.from('deal_redirect_clicks').insert({
        'deal_id': dealId,
        'trusted_partner_id': trustedPartnerId,
        'member_id': userId,
      });
    } catch (e) {
      // Tracking must never block the redirect.
      _logger.w('Failed to log website redirect click: $e');
    }
  }

  Future<Map<String, int>> getClickCounts(List<String> dealIds) async {
    if (dealIds.isEmpty) return {};
    try {
      final rows = await SupabaseService.instance.client.rpc(
        'get_deal_redirect_click_counts',
        params: {'p_deal_ids': dealIds},
      );
      final counts = <String, int>{};
      for (final row in (rows as List)) {
        final id = row['deal_id'] as String?;
        if (id != null) counts[id] = (row['click_count'] as num?)?.toInt() ?? 0;
      }
      return counts;
    } catch (e) {
      _logger.w('Failed to load website redirect click counts: $e');
      return {};
    }
  }

  /// Prefers an in-app browser tab so members return to Local Lekker on back.
  Future<bool> launch(Uri uri) async {
    final modes = kIsWeb
        ? const [LaunchMode.platformDefault]
        : const [
            LaunchMode.inAppBrowserView,
            LaunchMode.externalApplication,
            LaunchMode.platformDefault,
          ];
    for (final mode in modes) {
      try {
        if (await launchUrl(uri, mode: mode, webOnlyWindowName: '_blank')) {
          return true;
        }
      } catch (e) {
        _logger.w('Launch via $mode failed for $uri: $e');
      }
    }
    return false;
  }
}
