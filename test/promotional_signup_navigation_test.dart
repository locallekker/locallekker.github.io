import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_lekker/features/auth/members_home_page.dart';
import 'package:local_lekker/features/auth/members_signup_page.dart';
import 'package:local_lekker/features/auth/widgets/otp_verification_dialog.dart';
import 'package:local_lekker/features/member/member_terms_content.dart';
import 'package:local_lekker/features/member/member_terms_page.dart';
import 'package:local_lekker/features/payments/payments_feature.dart';
import 'package:local_lekker/services/navigation_service.dart';
import 'package:local_lekker/services/member_activation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const userId = 'ab100000-0000-0000-0000-000000000001';
  final requests = <http.Request>[];
  var termsAccepted = false;
  var failTerms = false;
  var failMarketingPreferences = false;
  var existingMarketingConsent = false;
  var subscriptionStatus = 'pending';
  final profile = <String, dynamic>{
    'id': userId,
    'role': 'member',
    'name': 'Signup',
    'surname': 'Fixture',
    'email': 'promo@example.test',
    'street': '1 Fixture Street',
    'suburb': 'Fixture Suburb',
    'city': 'Johannesburg',
    'province': 'Gauteng',
    'contact': '0820000000',
    'gender': 'Other',
    'ethnicity': 'Other',
    'date_of_birth': '1990-01-01',
    'created_at': '2026-11-11T00:00:00Z',
    'is_tp_member': false,
    'verified': false,
  };

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(
      envString:
          'SUPABASE_URL=https://promo-test.supabase.co\n'
          'SUPABASE_ANON_KEY=fixture',
    );
    final jwtPayload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'sub': userId,
              'exp':
                  DateTime.now()
                      .add(const Duration(hours: 1))
                      .millisecondsSinceEpoch ~/
                  1000,
            }),
          ),
        )
        .replaceAll('=', '');
    await Supabase.initialize(
      url: 'https://promo-test.supabase.co',
      anonKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        Object? body = <Object>[];
        if (request.url.path == '/auth/v1/token') {
          body = {
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.$jwtPayload.fixture',
            'refresh_token': 'fixture-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': userId,
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'promo@example.test',
              'app_metadata': <String, dynamic>{},
              'user_metadata': <String, dynamic>{},
              'created_at': '2026-11-11T00:00:00Z',
            },
          };
        } else if (request.url.path.endsWith('/rpc/get_my_role')) {
          body = 'member';
        } else if (request.url.path.endsWith('/rpc/accept_member_terms')) {
          termsAccepted = !failTerms;
          body = termsAccepted;
        } else if (request.url.path.endsWith(
          '/rpc/save_member_marketing_preferences',
        )) {
          body = !failMarketingPreferences;
        } else if (request.url.path.endsWith('/rpc/get_subscription_status')) {
          body = {'subscription_status': subscriptionStatus};
        } else if (request.url.path.endsWith(
          '/rpc/check_promo_eligibility_for_email',
        )) {
          body = {
            'participant_id': 'fixture-participant',
            'promotion_id': 'fixture-promotion',
            'name': 'One Month Free Trial',
            'free_months': 1,
            'initial_charge_cents': 100,
            'renewal_charge_cents': 9900,
          };
        } else if (request.url.path.endsWith('/profiles')) {
          body =
              request.url.queryParameters.containsKey('email') &&
                  !existingMarketingConsent
              ? null
              : {
                  ...profile,
                  'is_deactivated': existingMarketingConsent,
                  'marketing_email_consent': existingMarketingConsent,
                  'marketing_whatsapp_consent': existingMarketingConsent,
                  'subscription': subscriptionStatus,
                  'member_terms_accepted': termsAccepted,
                  'member_terms_version': termsAccepted
                      ? MemberTermsContent.termsVersion
                      : null,
                };
        }
        return http.Response(
          jsonEncode(body),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'promo@example.test',
      password: 'fixture',
    );
  });

  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    requests.clear();
    SharedPreferences.setMockInitialValues({});
    termsAccepted = false;
    failTerms = false;
    failMarketingPreferences = false;
    existingMarketingConsent = false;
    subscriptionStatus = 'pending';
  });

  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsOneWidget);
  }

  Future<void> closePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  }

  Future<void> completeSignupForm(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MembersSignupPage()));
    for (final entry in {
      'Email': 'promo@example.test',
      'Create Password': 'Fixture123!',
      'Confirm Password': 'Fixture123!',
      'Name': 'Signup',
      'Surname': 'Fixture',
      'Street Address': '1 Fixture Street',
      'Contact Number': '0820000000',
    }.entries) {
      final field = find.widgetWithText(TextFormField, entry.key);
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
      await tester.pump();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Pick Date'),
      -150,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Pick Date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    for (final entry in {
      'Gender': 'Other',
      'Ethnicity': 'Other',
      'Province': 'Gauteng',
      'City': 'Johannesburg',
      'Suburb': 'Other (enter manually)',
    }.entries) {
      final field = find.widgetWithText(
        DropdownButtonFormField<String>,
        entry.key,
      );
      await tester.scrollUntilVisible(
        field,
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      tester
          .widget<DropdownButton<String>>(
            find.descendant(
              of: field,
              matching: find.byType(DropdownButton<String>),
            ),
          )
          .onChanged!(entry.value);
      await tester.pump();
    }
    final suburbField = find.widgetWithText(TextFormField, 'Enter Suburb');
    await tester.ensureVisible(suburbField);
    await tester.enterText(suburbField, 'Fixture Suburb');
    FocusManager.instance.primaryFocus?.unfocus();
    final terms = find.widgetWithText(
      CheckboxListTile,
      'I have read and agree to the Local Lekker Club Terms and Conditions and acknowledge the Privacy Notice.',
    );
    await tester.ensureVisible(terms);
    await tester.tap(terms);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Create Account'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }

  Future<void> completeSignupVerification(WidgetTester tester) async {
    ScaffoldMessenger.of(
      tester.element(find.byType(MembersSignupPage)),
    ).clearSnackBars();
    await tester.ensureVisible(find.text('Create Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    final dialogFinder = find.byType(OtpVerificationDialog);
    expect(dialogFinder, findsOneWidget);
    final dialog = tester.widget<OtpVerificationDialog>(dialogFinder);
    Navigator.of(tester.element(dialogFinder)).pop();
    await dialog.onVerificationSuccess(userId);
    await tester.pumpAndSettle();
  }

  testWidgets('signup without marketing selection proceeds without opting in', (
    tester,
  ) async {
    failMarketingPreferences = true;
    await completeSignupForm(tester);
    for (final channel in ['Email', 'WhatsApp']) {
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, channel),
            )
            .value,
        isFalse,
      );
    }
    await completeSignupVerification(tester);
    await pumpUntil(tester, find.byType(PaymentRequiredScreen));
    expect(
      requests.where(
        (request) =>
            request.url.path.endsWith('/rpc/save_member_marketing_preferences'),
      ),
      isEmpty,
    );
    await closePage(tester);
  });

  for (final channel in ['Email', 'WhatsApp']) {
    testWidgets('signup saves only the selected $channel marketing opt-in', (
      tester,
    ) async {
      await completeSignupForm(tester);
      final checkbox = find.widgetWithText(CheckboxListTile, channel);
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pump();
      await completeSignupVerification(tester);
      await pumpUntil(tester, find.byType(PaymentRequiredScreen));
      final request = requests.singleWhere(
        (request) =>
            request.url.path.endsWith('/rpc/save_member_marketing_preferences'),
      );
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['p_email_consent'], channel == 'Email');
      expect(body['p_whatsapp_consent'], channel == 'WhatsApp');
      await closePage(tester);
    });
  }

  testWidgets('unchecking existing marketing opt-ins saves both as false', (
    tester,
  ) async {
    existingMarketingConsent = true;
    await completeSignupForm(tester);
    for (final channel in ['Email', 'WhatsApp']) {
      final checkbox = find.widgetWithText(CheckboxListTile, channel);
      expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
      await tester.ensureVisible(checkbox);
      await tester.pumpAndSettle();
      await tester.tap(checkbox);
      await tester.pump();
    }
    await completeSignupVerification(tester);
    await pumpUntil(tester, find.byType(PaymentRequiredScreen));
    final request = requests.singleWhere(
      (request) =>
          request.url.path.endsWith('/rpc/save_member_marketing_preferences'),
    );
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['p_email_consent'], isFalse);
    expect(body['p_whatsapp_consent'], isFalse);
    await closePage(tester);
  });

  testWidgets('accepting signup terms opens the eligible one-month offer', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MemberTermsPage()));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Accept & Proceed to Payment'));
    await pumpUntil(tester, find.byType(PaymentRequiredScreen));
    await pumpUntil(tester, find.textContaining('One Month Free Trial:'));
    expect(
      find.text(
        'One Month Free Trial: Pay R1.00 now, then get 1 month(s) free. '
        'After that, auto-renews at R99.00/month.',
      ),
      findsOneWidget,
    );
    expect(find.text('Proceed to Payment'), findsNothing);
    await tester.ensureVisible(find.text('Activate Entry Offer'));
    await tester.tap(find.text('Activate Entry Offer'));
    await pumpUntil(tester, find.byType(PaymentOptionsScreen));
    final options = tester.widget<PaymentOptionsScreen>(
      find.byType(PaymentOptionsScreen),
    );
    expect(options.selectedPlan, 'promotion_intro');
    expect(options.planDetails['promotion_id'], 'fixture-promotion');
    expect(options.planDetails['participant_id'], 'fixture-participant');
    expect(options.planDetails['free_months'], 1);
    expect(options.planDetails['price'], 1);
    expect(
      requests.where(
        (request) =>
            request.url.path.contains('subscription-billing') ||
            request.url.path.endsWith('/promotion_participant_emails') &&
                request.method != 'GET',
      ),
      isEmpty,
    );
    await closePage(tester);
  });

  testWidgets(
    'failed terms acceptance stays retryable without claiming an offer',
    (tester) async {
      failTerms = true;
      await tester.pumpWidget(const MaterialApp(home: MemberTermsPage()));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Accept & Proceed to Payment'));
      await tester.pumpAndSettle();
      expect(
        find.text('Failed to save acceptance. Try again.'),
        findsOneWidget,
      );
      expect(find.byType(PaymentRequiredScreen), findsNothing);
      expect(
        requests.where(
          (request) => request.url.path.endsWith(
            '/rpc/check_promo_eligibility_for_email',
          ),
        ),
        isEmpty,
      );
      await closePage(tester);
    },
  );

  testWidgets('ordinary sign-in keeps pending members in browse mode', (
    tester,
  ) async {
    termsAccepted = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  NavigationService().navigateToHomeAfterAuth(context),
              child: const Text('Sign in'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sign in'));
    await pumpUntil(tester, find.byType(MembersHomePage));
    expect(find.byType(PaymentRequiredScreen), findsNothing);
    await closePage(tester);
  });

  testWidgets(
    'signup with accepted terms goes directly to the promotional offer',
    (tester) async {
      termsAccepted = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => NavigationService().navigateToHomeAfterAuth(
                  context,
                  continueToPayment: true,
                ),
                child: const Text('Complete signup'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Complete signup'));
      await pumpUntil(tester, find.byType(PaymentRequiredScreen));
      await pumpUntil(tester, find.textContaining('One Month Free Trial:'));
      await closePage(tester);
    },
  );

  testWidgets('skipping signup payment opens deals instead of the auth page', (
    tester,
  ) async {
    termsAccepted = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () =>
                          NavigationService().navigateToHomeAfterAuth(
                            context,
                            continueToPayment: true,
                          ),
                      child: const Text('Complete signup'),
                    ),
                  ),
                ),
              ),
              child: const Text('Signup/sign-in entry'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Signup/sign-in entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete signup'));
    await pumpUntil(tester, find.byType(PaymentRequiredScreen));
    final skip = find.text('Skip for now – browse deals');
    await tester.ensureVisible(skip);
    await tester.pumpAndSettle();
    await tester.tap(skip);
    await pumpUntil(tester, find.byType(MembersHomePage));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('Signup/sign-in entry', skipOffstage: false),
      findsNothing,
    );
    expect(Supabase.instance.client.auth.currentUser?.id, userId);
    expect(
      requests.where(
        (request) =>
            request.url.path.endsWith('/logout') ||
            request.url.path.contains('subscription-billing'),
      ),
      isEmpty,
    );
    await closePage(tester);
  });

  testWidgets('skipping in-app activation returns to the calling deal page', (
    tester,
  ) async {
    termsAccepted = true;
    var activationReturned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await MemberActivationService().startActivation(
                  context,
                  potentialSavings: 25,
                );
                activationReturned = true;
              },
              child: const Text('Activate from deal'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Activate from deal'));
    await pumpUntil(tester, find.byType(PaymentRequiredScreen));
    final skip = find.text('Skip for now – browse deals');
    await tester.ensureVisible(skip);
    await tester.pumpAndSettle();
    await tester.tap(skip);
    await tester.pumpAndSettle();
    expect(find.text('Activate from deal'), findsOneWidget);
    expect(find.byType(PaymentRequiredScreen), findsNothing);
    expect(activationReturned, isTrue);
    expect(Supabase.instance.client.auth.currentUser?.id, userId);
    await closePage(tester);
  });

  testWidgets(
    'active membership is not asked to pay again after accepting terms',
    (tester) async {
      termsAccepted = true;
      subscriptionStatus = 'active';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => NavigationService().navigateToHomeAfterAuth(
                  context,
                  continueToPayment: true,
                ),
                child: const Text('Continue'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Continue'));
      await pumpUntil(tester, find.byType(MembersHomePage));
      expect(find.byType(PaymentRequiredScreen), findsNothing);
      await closePage(tester);
    },
  );
}
