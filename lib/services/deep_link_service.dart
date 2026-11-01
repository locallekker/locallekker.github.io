import 'package:app_links/app_links.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  late final AppLinks _appLinks;
  StreamSubscription? _sub;
  final StreamController<String?> _linkController =
      StreamController<String?>.broadcast();

  Stream<String?> get linkStream => _linkController.stream;

  bool _isAuthCallback(Uri uri) {
    return uri.host == 'auth' && uri.path == '/callback';
  }

  bool _isSignupCompletion(Uri uri) {
    if (kIsWeb && uri.queryParameters['type']?.toLowerCase() == 'signup_reminder') {
      return true;
    }

    if (uri.scheme != 'locallekker') return false;

    final isDirectSignupLink =
      uri.host == 'signup' && uri.path == '/complete';
    final isReminderAuthLink =
      _isAuthCallback(uri) &&
      uri.queryParameters['type']?.toLowerCase() == 'signup_reminder';
    return isDirectSignupLink || isReminderAuthLink;
  }

  String? _extractToken(Uri uri, String tokenName) {
    if (uri.fragment.contains('$tokenName=')) {
      return _extractTokenFromFragment(uri.fragment, tokenName);
    }
    return uri.queryParameters[tokenName];
  }

  Map<String, String>? _extractPasswordResetDataFromUri(Uri uri) {
    final code = _extractToken(uri, 'code');
    final accessToken = _extractToken(uri, 'access_token');
    final refreshToken = _extractToken(uri, 'refresh_token');
    final type = _extractToken(uri, 'type')?.toLowerCase();

    if (kDebugMode) {
      print(
        'DeepLinkService: Inspect URI for reset - uri=$uri, code=${code != null}, accessToken=${accessToken != null}, type=$type',
      );
    }

    // PKCE recovery can arrive either on locallekker://auth/callback OR on
    // a web localhost URL after Supabase verify redirect.
    if (code != null && (_isAuthCallback(uri) || type == 'recovery')) {
      return {'code': code};
    }

    // Legacy token flow.
    if (accessToken != null && (type == 'recovery' || type == 'magiclink')) {
      return {
        'accessToken': accessToken,
        'refreshToken': ?refreshToken,
      };
    }

    return null;
  }

  void init() {
    _appLinks = AppLinks();

    // Handle initial link when app is launched from deep link
    _appLinks.getInitialLink().then((link) {
      if (link case final uri?) {
        _handleDeepLink(uri.toString());
      }
    });

    // Handle deep links when app is already running
    _sub = _appLinks.uriLinkStream.listen((link) {
      _handleDeepLink(link.toString());
    });
  }

  // Check for initial link synchronously - returns password reset data if present
  // Returns either {'code': 'xxx'} for PKCE flow or {'accessToken': 'xxx', 'refreshToken': 'xxx'} for token flow
  Future<Map<String, String>?> checkForPasswordResetLink() async {
    try {
      if (kDebugMode) {
        print('DeepLinkService: Checking for password reset link...');
      }

      final link = await _appLinks.getInitialLink();

      if (kDebugMode) {
        print('DeepLinkService: Initial link = $link');
      }

      final urisToCheck = <Uri>[];
      if (link != null) {
        urisToCheck.add(Uri.parse(link.toString()));
      }

      // On web, AppLinks may return null/stripped values. Uri.base is the
      // authoritative callback URL currently loaded in the browser.
      if (kIsWeb) {
        urisToCheck.add(Uri.base);
      }

      for (final uri in urisToCheck) {
        if (kDebugMode) {
          print(
            'DeepLinkService: Parsed URI - host: ${uri.host}, path: ${uri.path}',
          );
          print('DeepLinkService: URI fragment: ${uri.fragment}');
          print('DeepLinkService: URI query params: ${uri.queryParameters}');
        }

        final resetData = _extractPasswordResetDataFromUri(uri);
        if (resetData != null) {
          if (kDebugMode) {
            print('DeepLinkService: ✅ Password reset callback detected!');
          }
          return resetData;
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking for password reset link: $e');
      }
      return null;
    }
  }

  Future<bool> checkForSignupCompletionLink() async {
    try {
      // Uri.base is available immediately in browsers and does not depend on
      // app_links providing a web implementation.
      if (kIsWeb && _isSignupCompletion(Uri.base)) {
        return true;
      }

      final link = await _appLinks.getInitialLink();
      if (link != null && _isSignupCompletion(Uri.parse(link.toString()))) {
        return true;
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking for signup completion link: $e');
      }
      return false;
    }
  }

  void _handleDeepLink(String link) {
    if (kDebugMode) {
      print('DeepLinkService: Handling deep link: $link');
    }

    // Parse the URL to extract authentication tokens
    final uri = Uri.parse(link);

    if (_isSignupCompletion(uri)) {
      _linkController.add('signup_completion');
      return;
    }

    final resetData = _extractPasswordResetDataFromUri(uri);
    if (resetData != null) {
      if (resetData.containsKey('code')) {
        _linkController.add('password_reset_pkce:${resetData['code']}');
      } else if (resetData.containsKey('accessToken')) {
        _handlePasswordReset(
          resetData['accessToken']!,
          resetData['refreshToken'],
        );
      }
      return;
    }

    // Check if this is an authentication callback for non-recovery auth types
    if (_isAuthCallback(uri)) {
      final accessToken = _extractToken(uri, 'access_token');
      final refreshToken = _extractToken(uri, 'refresh_token');
      final type = _extractToken(uri, 'type')?.toLowerCase();

      if (kDebugMode) {
        print(
          'DeepLinkService: Parsed tokens - accessToken: ${accessToken != null}, type: $type, refreshToken: ${refreshToken != null}',
        );
      }

      if (accessToken != null && type == 'signup') {
        _handleSignupConfirmation(accessToken, refreshToken);
      } else if (accessToken != null && type == 'invite') {
        _handleInvite(accessToken, refreshToken);
      }
    }
    // Check if this is a Paystack payment callback
    else if (uri.scheme == 'locallekker' &&
        uri.host == 'payment' &&
        uri.path == '/callback') {
      // This is a Paystack payment callback
      _handlePaymentCallback(uri);
    }
  }

  String? _extractTokenFromFragment(String fragment, String tokenName) {
    final regex = RegExp('$tokenName=([^&]+)');
    final match = regex.firstMatch(fragment);
    return match?.group(1);
  }

  void _handlePasswordReset(String accessToken, String? refreshToken) {
    if (kDebugMode) {
      print(
        'DeepLinkService: Handling password reset with token: $accessToken',
      );
    }

    // Store the tokens for later use in password reset flow
    // You might want to navigate to a password reset screen
    _linkController.add('password_reset:$accessToken:$refreshToken');
  }

  void _handleSignupConfirmation(String accessToken, String? refreshToken) {
    if (kDebugMode) {
      print(
        'DeepLinkService: Handling signup confirmation with token: $accessToken',
      );
    }

    // Store the tokens for later use
    _linkController.add('signup_confirmation:$accessToken:$refreshToken');
  }

  void _handleInvite(String accessToken, String? refreshToken) {
    if (kDebugMode) {
      print('DeepLinkService: Handling invite with token: $accessToken');
    }

    // Store the tokens for later use
    _linkController.add('invite:$accessToken:$refreshToken');
  }

  void _handlePaymentCallback(Uri uri) {
    if (kDebugMode) {
      print('DeepLinkService: Handling Paystack payment callback: $uri');
    }

    // Extract payment reference from query parameters
    final reference = uri.queryParameters['reference'];
    final trxref = uri.queryParameters['trxref'];

    if (reference != null || trxref != null) {
      // Notify listeners about payment callback
      _linkController.add('payment_callback:${reference ?? trxref}');
    } else {
      if (kDebugMode) {
        print('DeepLinkService: Payment callback missing reference parameter');
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    _linkController.close();
  }

  // Method to manually handle a deep link (useful for testing)
  void handleManualLink(String link) {
    _handleDeepLink(link);
  }
}
