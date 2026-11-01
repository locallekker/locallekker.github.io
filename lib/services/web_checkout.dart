import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where Paystack should redirect the payer once the hosted checkout finishes.
///
/// The native `locallekker://` scheme is meaningless in a browser, so on web we
/// send Paystack back to the origin the member is already on.
String paystackCallbackUrl() {
  if (kIsWeb) {
    return webAppReturnUrl();
  }
  return dotenv.env['PAYSTACK_CALLBACK_URL'] ?? 'locallekker://payment/callback';
}

/// Origin + path of the currently loaded web app, without query/fragment.
String webAppReturnUrl() {
  final base = Uri.base;
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: base.path,
  ).toString();
}

/// Sends the browser to the Paystack hosted checkout page.
///
/// Uses `_self` rather than `_blank`: iOS Safari blocks `window.open` that is
/// not inside a synchronous user-gesture call stack, and the checkout URL only
/// becomes available after the async `/transaction/initialize` request. A
/// same-tab navigation is never popup-blocked, so iOS members reach the card
/// entry form the same way Android app members do.
Future<bool> openWebCheckout(String authorizationUrl) {
  return launchUrl(
    Uri.parse(authorizationUrl),
    webOnlyWindowName: '_self',
  );
}
