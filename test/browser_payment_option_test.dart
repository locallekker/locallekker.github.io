import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/widgets/browser_payment_option.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    dotenv.clean();
  });

  test('wallet browser option is disabled by default', () {
    dotenv.loadFromString(envString: 'UNRELATED_SETTING=true');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(isGooglePayBrowserCheckoutEnabled, isFalse);
  });

  test('wallet browser option requires explicit Android enablement', () {
    dotenv.loadFromString(envString: 'PAYSTACK_GOOGLE_PAY_ENABLED=true');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(isGooglePayBrowserCheckoutEnabled, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(isGooglePayBrowserCheckoutEnabled, isFalse);
  });

  for (final url in [
    'http://checkout.paystack.com/example',
    'https://paystack.com.example.org/example',
    'locallekker://payment/callback',
  ]) {
    testWidgets('invalid checkout URL surfaces a retryable error: $url', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BrowserPaymentOption(authorizationUrl: url)),
        ),
      );
      expect(find.text('Pay in browser'), findsOneWidget);
      await tester.tap(find.text('Pay in browser'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Could not open your browser. Try again or pay by card below.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
