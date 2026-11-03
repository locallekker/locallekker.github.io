import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_lekker/features/auth/deal_authorization_request_page.dart';
import 'package:local_lekker/features/auth/deal_selection_page.dart';
import 'package:local_lekker/features/auth/members_home_page.dart';
import 'package:local_lekker/features/auth/trusted_partner_shop_page.dart';
import 'package:local_lekker/features/auth/welcome_page.dart';
import 'package:local_lekker/features/members/restaurant_deal_request_page.dart';
import 'package:local_lekker/models/discount.dart';
import 'package:local_lekker/services/discount_service.dart';
import 'package:local_lekker/services/guest_analytics_service.dart';
import 'package:local_lekker/services/member_activation_service.dart';
import 'package:local_lekker/services/navigation_service.dart';
import 'package:local_lekker/services/supabase_service.dart';
import 'package:local_lekker/widgets/age_verification_dialog.dart';
import 'package:local_lekker/widgets/guest_sign_in_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  final deal = <String, dynamic>{
    'id': 'd0000000-0000-0000-0000-000000000001',
    'trusted_partner_id': 'a0000000-0000-0000-0000-000000000001',
    'business_id': 'b0000000-0000-0000-0000-000000000001',
    'name': 'Guest fixture deal',
    'item_name': 'Fixture item',
    'item_price': 200,
    'percentage': 25,
    'deal_type': 'standard',
    'is_active': true,
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
  };
  final partner = <String, dynamic>{
    'id': deal['business_id'],
    'owner_member_id': deal['trusted_partner_id'],
    'name': 'Fixture partner',
    'category': 'Restaurant',
    'city': 'Cape Town',
  };

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://guest-test.supabase.co',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        Object body = <Object>[];
        if (request.url.path.endsWith('/trusted_partner_discounts')) {
          final category = request.url.queryParameters['deal_category'];
          final createdAt = request.url.queryParameters['created_at'];
          body = category != null || createdAt != null ? <Object>[] : [deal];
        } else if (request.url.path.endsWith('/guest_business_catalogue')) {
          final hasFlag = [
            'sells_fresh_produce',
            'sells_alcohol',
            'offers_sports_activities',
          ].any(request.url.queryParameters.containsKey);
          body = hasFlag ? <Object>[] : [partner];
        } else if (request.url.path.endsWith(
          '/rpc/discount_accepts_in_app_payment',
        )) {
          body = true;
        }
        return http.Response(
          jsonEncode(body),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    SupabaseService.applyClientCapabilities(Supabase.instance.client);
  });

  tearDownAll(() => Supabase.instance.dispose());

  setUp(() {
    requests.clear();
    DiscountService.invalidateActiveDealsCache();
    GuestAnalyticsService().resetSessionForTesting();
  });

  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  void expectNoMemberWrites() {
    const allowedRpcs = [
      '/rpc/discount_accepts_in_app_payment',
      '/rpc/record_guest_visit',
      '/rpc/record_guest_deal_request',
    ];
    expect(
      requests.where(
        (r) =>
            r.method != 'GET' &&
            !allowedRpcs.any((rpc) => r.url.path.endsWith(rpc)),
      ),
      isEmpty,
    );
    expect(
      requests.where(
        (r) =>
            r.url.path.endsWith('/profiles') ||
            r.url.path.endsWith('/subscriptions') ||
            r.url.path.endsWith('/user_qr_codes'),
      ),
      isEmpty,
    );
  }

  List<Map<String, dynamic>> guestRequestLogs() => requests
      .where((r) => r.url.path.endsWith('/rpc/record_guest_deal_request'))
      .map((r) => Map<String, dynamic>.from(jsonDecode(r.body) as Map))
      .toList();

  void expectGuestRequestLogged(double? savings) {
    final logs = guestRequestLogs();
    expect(logs, hasLength(1));
    expect(logs.single['p_discount_id'], deal['id']);
    expect(logs.single['p_potential_savings'], savings);
    expect(logs.single['p_guest_id'], isA<String>());
  }

  test('unauthenticated launch resolves to the member dashboard', () async {
    expect(
      await NavigationService().getInitialScreen(),
      isA<MembersHomePage>(),
    );
    expect(
      SupabaseService.instance.businessCatalogueTable,
      'guest_business_catalogue',
    );
    expect(requests, isEmpty);
    expectNoMemberWrites();
  });

  for (final afterPayment in [false, true]) {
    testWidgets(
      'missing session after ${afterPayment ? 'payment' : 'auth'} returns to guest browsing',
      (tester) async {
        await open(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => afterPayment
                    ? NavigationService().navigateToHomeAfterPayment(context)
                    : NavigationService().navigateToHomeAfterAuth(context),
                child: const Text('Continue'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.byType(MembersHomePage), findsOneWidget);
        expect(find.byType(GuestSignInBanner), findsOneWidget);
        expectNoMemberWrites();
      },
    );
  }

  testWidgets('banner is dismissible and browsing remains accessible', (
    tester,
  ) async {
    await open(tester, const MembersHomePage());
    expect(find.byType(GuestSignInBanner), findsOneWidget);
    expect(find.text('Find Deals'), findsOneWidget);
    final visits = requests
        .where((r) => r.url.path.endsWith('/rpc/record_guest_visit'))
        .toList();
    expect(visits, hasLength(1));
    final guestId = (jsonDecode(visits.single.body) as Map)['p_guest_id'];
    expect(
      (await SharedPreferences.getInstance()).getString(
        GuestAnalyticsService.guestIdKey,
      ),
      guestId,
    );
    await tester.tap(find.byTooltip('Close sign-in banner'));
    await tester.pumpAndSettle();
    expect(find.byType(GuestSignInBanner), findsNothing);

    await tester.tap(find.text('Find Deals'));
    await tester.pumpAndSettle();
    expect(find.byType(DealSelectionPage), findsOneWidget);
    await tester.tap(find.text('Deals').first);
    await tester.pumpAndSettle();
    expect(find.text('Guest fixture deal'), findsWidgets);
    expect(
      requests.any((r) => r.url.path.endsWith('/guest_business_catalogue')),
      isTrue,
    );
    expect(requests.any((r) => r.url.path.endsWith('/businesses')), isFalse);
    expectNoMemberWrites();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(GuestSignInBanner), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'guest profile action opens authentication, not profile editing',
    (tester) async {
      await open(tester, const MembersHomePage());
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomePage), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expectNoMemberWrites();
    },
  );

  testWidgets('guest request gate shows exact savings and never authorizes', (
    tester,
  ) async {
    bool? allowed;
    await open(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              allowed = await MemberActivationService().ensureCanRequestDeal(
                context,
                savings: 123.45,
              );
            },
            child: const Text('Request'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();
    expect(find.text('You could save R123.45 on this deal'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(allowed, isFalse);
    expectNoMemberWrites();
  });

  for (final fixture in [
    ('standard', <String, dynamic>{'quantity': 3}, '150.00'),
    (
      'weight',
      <String, dynamic>{'is_weight_based': true, 'quantity': 500},
      '25.00',
    ),
    (
      'percent_item',
      <String, dynamic>{
        'deal_type': 'percent_item',
        'requires_manual_price': true,
        'quantity': 2,
      },
      '100.00',
    ),
    (
      'buy_get',
      <String, dynamic>{
        'deal_type': 'buy_get',
        'quantity': 2,
        'custom_data': {'buy_item_price': 200, 'total_price': 150},
      },
      '100.00',
    ),
  ]) {
    testWidgets(
      '${fixture.$1} preview passes quantity-adjusted savings to sign-in',
      (tester) async {
        await open(
          tester,
          DealAuthorizationRequestPage(deal: {...deal, ...fixture.$2}),
        );
        final submit = find.text('Submit Authorization Request');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(
          find.text('You could save R${fixture.$3} on this deal'),
          findsOneWidget,
        );
        expectNoMemberWrites();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Submit Authorization Request'), findsOneWidget);
      },
    );
  }

  testWidgets('restaurant bill preview shows savings before authentication', (
    tester,
  ) async {
    final discount = Discount.fromJson({
      ...deal,
      'deal_type': 'restaurant_food_percent',
      'custom_data': {'percentage': 25},
    });
    await open(tester, RestaurantDealRequestPage(discount: discount));
    await tester.enterText(find.byType(TextField).first, '400');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Send request').last);
    await tester.pumpAndSettle();
    expect(find.text('You could save R100.00 on this deal'), findsOneWidget);
    expectGuestRequestLogged(100.0);
    expectNoMemberWrites();
  });

  testWidgets(
    'partner shop request uses calculated savings without choosing payment',
    (tester) async {
      await open(tester, TrustedPartnerShopPage(partner: partner));
      await tester.tap(find.text('Guest fixture deal').first);
      await tester.pumpAndSettle();
      final request = find.text('Request Deal');
      await tester.tap(request);
      await tester.pumpAndSettle();
      expect(find.text('You could save R50.00 on this deal'), findsOneWidget);
      expectGuestRequestLogged(50.0);
      expectNoMemberWrites();
    },
  );

  testWidgets('bill discount dialog routes guests with bill savings', (
    tester,
  ) async {
    final discount = Discount.fromJson({
      ...deal,
      'deal_type': 'bill_discount',
      'is_bill_discount': true,
      'bill_discount_data': {'isPercentage': true},
    });
    await open(
      tester,
      Scaffold(
        body: BillDiscountDialog(
          discount: discount,
          trustedPartnerName: 'Fixture partner',
          deal: {
            ...deal,
            'trusted_partners': {
              'business_name': 'Fixture partner',
              'business_id': deal['business_id'],
            },
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '400');
    await tester.pumpAndSettle();
    final request = find.text('Request Authorization');
    await tester.ensureVisible(request);
    await tester.tap(request);
    await tester.pumpAndSettle();
    expect(find.text('You could save R100.00 on this deal'), findsOneWidget);
    expectGuestRequestLogged(100.0);
    expectNoMemberWrites();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('400'), findsOneWidget);
  });

  testWidgets(
    'checkout-priced BOGO has an auth action without invented savings',
    (tester) async {
      final discount = Discount.fromJson({
        ...deal,
        'deal_type': 'restaurant_bogo',
        'custom_data': {
          'pricing_mode': 'checkout',
          'item_name': 'Fixture item',
        },
      });
      await open(tester, RestaurantDealRequestPage(discount: discount));
      await tester.tap(find.text('Sign up or sign in to redeem'));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomePage), findsOneWidget);
      expect(find.textContaining('You could save'), findsNothing);
      expectGuestRequestLogged(null);
      expectNoMemberWrites();
    },
  );

  testWidgets('guest banner fits a narrow phone and sign-in action works', (
    tester,
  ) async {
    var tapped = false;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuestSignInBanner(
            onSignIn: () => tapped = true,
            onDismiss: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sign up or sign in'));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guests must confirm age without writing a profile', (
    tester,
  ) async {
    bool? confirmed;
    await open(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              confirmed = await ensureMemberIsAgeVerified(context);
            },
            child: const Text('Local Sips'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Local Sips'));
    await tester.pumpAndSettle();
    expect(find.text('Age restricted'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Continue'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
    expectNoMemberWrites();
  });
}
