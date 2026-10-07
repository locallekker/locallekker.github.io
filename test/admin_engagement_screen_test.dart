import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/features/admin/admin_engagement_screen.dart';
import 'package:local_lekker/models/admin_engagement_report.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_engagement_fixtures.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  testWidgets('Shows report, date presets and partner/deal drilldown', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final periods = <DateTimeRange>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AdminEngagementScreen(
          loadReport: ({required start, required end}) async {
            periods.add(DateTimeRange(start: start, end: end));
            return AdminEngagementReport.fromMap(reportFixture());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Member signups'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('TP signups'), findsOneWidget);
    expect(find.text('Completed deal sales'), findsOneWidget);
    expect(periods.single.end.difference(periods.single.start).inDays, 30);
    await tester.tap(find.text('Last 7 days'));
    await tester.pumpAndSettle();
    expect(periods.last.end.difference(periods.last.start).inDays, 7);
    await tester.ensureVisible(find.text('Quiet Partner'));
    await tester.tap(find.text('Quiet Partner'));
    await tester.pumpAndSettle();
    expect(find.text('Quiet offer'), findsOneWidget);
    expect(find.text('No recorded engagement'), findsOneWidget);
    expect(find.text('partner@example.test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reports failures explicitly and retries without zero fallback', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AdminEngagementScreen(
          loadReport: ({required start, required end}) async {
            if (++attempts == 1) throw StateError('RPC unavailable');
            return AdminEngagementReport.fromMap(reportFixture());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Reporting could not be loaded'),
      findsOneWidget,
    );
    expect(find.text('Member signups'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Member signups'), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Search and discussion filter include partners without deals', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AdminEngagementScreen(
          loadReport: ({required start, required end}) async =>
              AdminEngagementReport.fromMap(
                reportFixture(
                  partners: [
                    partnerFixture(),
                    partnerFixture(
                      id: 'empty',
                      name: 'No Offers Partner',
                      deals: [],
                    ),
                    partnerFixture(
                      id: 'engaged',
                      name: 'Engaged Partner',
                      deals: [dealFixture(redemptions: 2)],
                    ),
                  ],
                ),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Engaged Partner'), findsNothing);
    expect(find.text('No Offers Partner'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Quiet offer');
    await tester.pumpAndSettle();
    expect(find.text('Quiet Partner'), findsOneWidget);
    expect(find.text('No Offers Partner'), findsNothing);
  });

  testWidgets('A slower old response cannot overwrite a newer date range', (
    tester,
  ) async {
    final old = Completer<AdminEngagementReport>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AdminEngagementScreen(
          loadReport: ({required start, required end}) {
            if (++calls == 1) return old.future;
            return Future.value(
              AdminEngagementReport.fromMap(
                reportFixture()..['member_signups'] = 77,
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Last 7 days'));
    await tester.pumpAndSettle();
    expect(find.text('77'), findsOneWidget);
    old.complete(AdminEngagementReport.fromMap(reportFixture()));
    await tester.pumpAndSettle();
    expect(find.text('77'), findsOneWidget);
    expect(find.text('12'), findsNothing);
  });

  testWidgets('Report and drilldown fit a narrow phone viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AdminEngagementScreen(
          loadReport: ({required start, required end}) async =>
              AdminEngagementReport.fromMap(reportFixture()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Quiet Partner'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Quiet Partner'));
    await tester.pumpAndSettle();
    expect(find.text('Quiet offer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
