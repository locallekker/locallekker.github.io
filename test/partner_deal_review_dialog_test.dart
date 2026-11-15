import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_lekker/features/admin/partner_deal_review_dialog.dart';
import 'package:local_lekker/features/auth/discount_management_page.dart';
import 'package:local_lekker/models/discount.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Discount deal(String id) => Discount(
  id: id,
  trustedPartnerId: 'partner',
  name: 'Deal $id',
  description: 'Special $id',
  itemName: 'Item $id',
  itemPrice: 100,
  percentage: 10,
  isActive: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  databaseUpdatedAt: '2026-01-01T00:00:00Z',
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-key',
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
  });

  testWidgets('all deals must be reviewed before saving and cancellation is safe',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Object? result = 'not closed';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () async {
            result = await showDialog<List<Map<String, dynamic>>>(
              context: context,
              builder: (_) => PartnerDealReviewDialog(
                partnerId: 'partner',
                lockedCategory: 'Fresh & Local',
                website: '',
                deals: [deal('one'), deal('two')],
              ),
            );
          },
          child: const Text('Open review'),
        )),
      ),
    ));
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(find.widgetWithText(
      ElevatedButton, 'Save partner and deals')).onPressed, isNull);
    await tester.tap(find.text('Deal one'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standard deals').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Deal'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<DiscountType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fixed Amount').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Deal Price (R)'), '80');
    await tester.tap(find.text('Update Deal'));
    await tester.pumpAndSettle();
    expect(find.text('Reviewed'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(
      ElevatedButton, 'Save partner and deals')).onPressed, isNull);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('fixed-price review returns the new discount and category',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () async {
            result = await showDialog<Map<String, dynamic>>(
              context: context,
              builder: (_) => EditDiscountDialog(
                discount: deal('one'),
                lockedDealCategory: 'Fresh & Local',
                reviewMode: true,
              ),
            );
          },
          child: const Text('Open editor'),
        )),
      ),
    ));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<DiscountType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fixed Amount').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Deal Price (R)'), '80');
    await tester.tap(find.text('Update Deal'));
    await tester.pumpAndSettle();
    expect(result?['fixedAmount'], 20);
    expect(result?['dealCategory'], 'Fresh & Local');
    expect(result?['dealType'], 'standard');
    expect(result?['customData'], isNull);
  });

  testWidgets('completed review returns one draft without saving it early',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<Map<String, dynamic>>? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () async {
            result = await showDialog<List<Map<String, dynamic>>>(
              context: context,
              builder: (_) => PartnerDealReviewDialog(
                partnerId: 'partner',
                lockedCategory: 'Fresh & Local',
                website: 'https://example.test',
                deals: [deal('one')],
              ),
            );
          },
          child: const Text('Open review'),
        )),
      ),
    ));
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deal one'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Website redirect').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.tap(find.text('Save partner and deals'));
    await tester.pumpAndSettle();
    expect(result, hasLength(1));
    expect(result!.single['id'], 'one');
    expect(result!.single['updated_at'], '2026-01-01T00:00:00Z');
    final details = result!.single['details'] as Map<String, dynamic>;
    expect(details['deal_type'], 'website_redirect');
    expect(details['deal_category'], 'Fresh & Local');
    expect(details['fixed_amount'], isNull);
  });
}
