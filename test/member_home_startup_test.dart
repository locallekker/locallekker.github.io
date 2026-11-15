import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_lekker/core/constants/deal_categories.dart';
import 'package:local_lekker/features/auth/members_home_page.dart';
import 'package:local_lekker/services/discount_service.dart';
import 'package:local_lekker/services/guest_analytics_service.dart';
import 'package:local_lekker/services/supabase_service.dart';
import 'package:local_lekker/widgets/category_entry_banner.dart';
import 'package:local_lekker/widgets/loading_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  Completer<void>? categoryGate;
  Completer<void>? countsGate;
  bool failCategory = false;
  bool emptyCategories = false;
  const categories = [
    kFreshLocalCategory,
    kLocalSipsCategory,
    kLocalEatsCategory,
    kLocallyActiveCategory,
  ];
  final partner = {
    'id': 'b0000000-0000-0000-0000-000000000001',
    'owner_member_id': 'a0000000-0000-0000-0000-000000000001',
    'name': 'Startup fixture partner',
    'category': 'Restaurant',
    'city': 'Johannesburg',
  };
  final otherCityPartner = {
    'id': 'b0000000-0000-0000-0000-000000000002',
    'owner_member_id': 'a0000000-0000-0000-0000-000000000002',
    'name': 'Other city partner',
    'category': 'Restaurant',
    'city': 'Cape Town',
  };
  final deals = [
    for (final owner in [partner, otherCityPartner])
      for (var index = 0; index < categories.length; index++)
        {
          'id': 'startup-deal-${owner['id']}-$index',
          'name': 'Startup deal $index',
          'business_id': owner['id'],
          'trusted_partner_id': owner['owner_member_id'],
          'deal_category': categories[index],
          'is_active': true,
          'offers_delivery': false,
          'created_at': '2020-01-01T00:00:00Z',
        },
  ];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://startup-test.supabase.co',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final select = request.url.queryParameters['select'] ?? '';
        final isCategoryQuery = select.contains('deal_category');
        if (isCategoryQuery) {
          await categoryGate?.future;
          if (failCategory) {
            return http.Response(
              jsonEncode({'message': 'Catalogue unavailable'}),
              503,
              headers: {'content-type': 'application/json'},
            );
          }
        }
        Object body = <Object>[];
        if (request.url.path.endsWith('/trusted_partner_discounts')) {
          body = emptyCategories && isCategoryQuery ? <Object>[] : deals;
        } else if (request.url.path.endsWith('/guest_business_catalogue')) {
          if (select.contains('address')) await countsGate?.future;
          body = [partner, otherCityPartner];
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
    categoryGate = null;
    countsGate = null;
    failCategory = false;
    emptyCategories = false;
    SharedPreferences.setMockInitialValues({
      'selected_province': 'Gauteng',
      'selected_city': 'Johannesburg',
    });
    DiscountService.invalidateActiveDealsCache();
    GuestAnalyticsService().resetSessionForTesting();
  });

  Future<void> openHome(WidgetTester tester, {double width = 400}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MembersHomePage()));
    await tester.pump();
  }

  void expectCompleteHome() {
    expect(find.byType(LoadingScreen), findsNothing);
    expect(find.byType(CategoryEntryBanner), findsNWidgets(5));
    for (final category in categories) {
      expect(find.text(category), findsOneWidget);
    }
    final banners = find
        .byType(CategoryEntryBanner)
        .evaluate()
        .map((element) => element.widget)
        .whereType<CategoryEntryBanner>();
    for (final banner in banners) {
      // Partners counts the whole catalogue; categories use the saved city.
      expect(banner.partnerCount, banner.title == 'Partners' ? 2 : 1);
      expect(banner.dealCount, greaterThan(0));
    }
  }

  testWidgets('keeps the branded background until every category is ready', (
    tester,
  ) async {
    categoryGate = Completer<void>();
    await openHome(tester);

    expect(find.byType(LoadingScreen), findsOneWidget);
    expect(find.byType(CategoryEntryBanner), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));

    expect(find.byType(LoadingScreen), findsOneWidget);
    expect(find.byType(CategoryEntryBanner), findsNothing);
    final logo = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image == const AssetImage('assets/locallekker_logo.png'),
    );
    expect(logo, findsOneWidget);
    final logoFade = find.ancestor(
      of: logo,
      matching: find.byType(FadeTransition),
    );
    for (final fade in tester.widgetList<FadeTransition>(logoFade)) {
      expect(fade.opacity.value, 1);
    }
    final logoScale = find.ancestor(of: logo, matching: find.byType(Transform));
    expect(tester.widget<Transform>(logoScale.first).transform.entry(0, 0), 1);
    await tester.pump(const Duration(seconds: 20));
    expect(find.byType(LoadingScreen), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(logo, findsOneWidget);

    categoryGate!.complete();
    await tester.pumpAndSettle();
    expectCompleteHome();
    expect(tester.takeException(), isNull);
  });

  testWidgets('loads every category with two parallel catalogue queries', (
    tester,
  ) async {
    await openHome(tester);
    await tester.pumpAndSettle();
    expectCompleteHome();

    final categoryQueries = requests.where(
      (request) =>
          (request.url.queryParameters['select'] ?? '').contains(
            'deal_category',
          ) ||
          (request.url.queryParameters['select'] ?? '').contains(
            'sells_fresh_produce',
          ),
    );
    expect(categoryQueries, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fast loading keeps the logo until the dashboard fade begins', (
    tester,
  ) async {
    await openHome(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LoadingScreen), findsOneWidget);
    expect(find.byType(CategoryEntryBanner), findsNothing);

    await tester.pumpAndSettle();
    expectCompleteHome();
    expect(tester.takeException(), isNull);
  });

  testWidgets('partner totals must also finish before the home fade begins', (
    tester,
  ) async {
    countsGate = Completer<void>();
    await openHome(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(CategoryEntryBanner), findsNothing);
    expect(find.byType(LoadingScreen), findsOneWidget);

    countsGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(CategoryEntryBanner), findsNWidgets(5));
    expect(find.byType(LoadingScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    final homeFade = find.ancestor(
      of: find.byKey(const ValueKey('home-ready')),
      matching: find.byType(FadeTransition),
    );
    final opacity = tester.widget<FadeTransition>(homeFade.first).opacity.value;
    expect(opacity, greaterThan(0));
    expect(opacity, lessThan(1));
    final homeSlide = find.ancestor(
      of: find.byKey(const ValueKey('home-ready')),
      matching: find.byType(SlideTransition),
    );
    expect(homeSlide, findsWidgets);
    final slideOffset = tester
        .widget<SlideTransition>(homeSlide.first)
        .position
        .value;
    expect(slideOffset.dy, greaterThan(0));
    expect(slideOffset.dy, lessThan(0.015));
    await tester.pumpAndSettle();
    expectCompleteHome();
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed loads are checked again every 5 seconds', (tester) async {
    failCategory = true;
    await openHome(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.byType(LoadingScreen), findsOneWidget);
    expect(find.byType(CategoryEntryBanner), findsNothing);
    expect(find.text('Try again'), findsNothing);

    failCategory = false;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expectCompleteHome();
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated failures offer a manual retry while checks continue', (
    tester,
  ) async {
    failCategory = true;
    await openHome(tester);
    for (var i = 0; i < 7; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(CategoryEntryBanner), findsNothing);

    failCategory = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expectCompleteHome();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a slow request keeps loading and completes without restart', (
    tester,
  ) async {
    categoryGate = Completer<void>();
    await openHome(tester);
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(CategoryEntryBanner), findsNothing);

    categoryGate!.complete();
    await tester.pumpAndSettle();
    expectCompleteHome();
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful empty categories reveal only Partners', (
    tester,
  ) async {
    emptyCategories = true;
    await openHome(tester, width: 600);
    await tester.pumpAndSettle();

    expect(find.byType(LoadingScreen), findsNothing);
    expect(find.byType(CategoryEntryBanner), findsOneWidget);
    expect(find.text('Partners'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving during startup does not update the disposed page', (
    tester,
  ) async {
    categoryGate = Completer<void>();
    await openHome(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    categoryGate!.complete();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
