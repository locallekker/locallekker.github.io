import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/features/admin/admin_guest_conversion_screen.dart';
import 'package:local_lekker/models/guest_conversion_report.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDownAll(() => Supabase.instance.dispose());

  final report = GuestConversionReport.fromMap({
    'browsing_guests': 40,
    'converted_browsing_guests': 9,
    'requesting_guests': 10,
    'request_attempts': '14',
    'converted_requesting_guests': 4,
    'signup_conversions': 3,
    'signin_conversions': 1,
    'potential_savings_total': '512.50',
    'deals': [
      {
        'discount_id': 'd1',
        'deal_name': 'Burger special',
        'business_name': 'Fixture Grill',
        'attempts': 9,
        'guests': 6,
        'converted_guests': 3,
        'potential_savings': 300,
      },
      {
        'discount_id': null,
        'deal_name': null,
        'business_name': null,
        'attempts': 5,
        'guests': 4,
        'converted_guests': 0,
        'potential_savings': 0,
      },
    ],
  });

  Future<void> pump(WidgetTester tester, GuestConversionReportLoader loader) {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      MaterialApp(home: AdminGuestConversionScreen(loadReport: loader)),
    );
  }

  test('report parses numbers and computes funnel rates', () {
    expect(report.requestAttempts, 14);
    expect(report.potentialSavingsTotal, 512.5);
    expect(report.requestRate, 0.25);
    expect(report.requestConversionRate, 0.4);
    expect(report.deals.first.conversionRate, 0.5);
    expect(report.deals.last.dealName, 'Removed deal');
    expect(GuestConversionReport.fromMap({}).requestConversionRate, 0);
  });

  testWidgets('shows guest funnel, conversions and requested deals', (
    tester,
  ) async {
    final ranges = <(DateTime, DateTime)>[];
    await pump(tester, ({required start, required end}) async {
      ranges.add((start, end));
      return report;
    });
    await tester.pumpAndSettle();

    expect(find.text('Browsing guests'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('4 (40.0%)'), findsOneWidget);
    expect(find.text('New signups'), findsOneWidget);
    expect(find.text('Existing sign-ins'), findsOneWidget);
    expect(
      find.text('25.0% of browsing guests tried to request a deal.'),
      findsOneWidget,
    );
    expect(find.text('Burger special'), findsOneWidget);
    expect(find.textContaining('Fixture Grill'), findsOneWidget);
    expect(find.textContaining('3 converted (50.0%)'), findsOneWidget);
    expect(find.text('Removed deal'), findsOneWidget);
    expect(ranges.single.$2.difference(ranges.single.$1).inDays, 30);

    await tester.tap(find.text('Last 7 days'));
    await tester.pumpAndSettle();
    expect(ranges, hasLength(2));
    expect(ranges.last.$2.difference(ranges.last.$1).inDays, 7);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows retryable error when the report fails', (tester) async {
    var calls = 0;
    await pump(tester, ({required start, required end}) async {
      calls++;
      if (calls == 1) throw Exception('missing rpc');
      return GuestConversionReport.fromMap({'deals': []});
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be loaded'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('No guest deal requests in this period yet.'),
      findsOneWidget,
    );
  });
}
