import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/features/business/restaurant_deal_dialog.dart';
import 'package:local_lekker/models/discount.dart';
import 'package:local_lekker/models/restaurant_deal.dart';

Discount bogo({String? mode}) => Discount(
  id: 'deal-id',
  trustedPartnerId: 'partner-id',
  name: 'Cocktails',
  description: '',
  itemName: 'cocktails',
  itemPrice: 0,
  percentage: 0,
  dealType: RestaurantDealType.bogo.key,
  customData: {
    'item_name': 'cocktails',
    'item_price': 95,
    'pricing_mode': ?mode,
  },
  isActive: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Future<void> openForm(WidgetTester tester, {Discount? existing}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RestaurantDealDialog(
          trustedPartnerId: 'partner-id',
          existing: existing,
        ),
      ),
    ),
  );
}

CheckboxListTile checkbox(WidgetTester tester, String label) => tester
    .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, label));

void main() {
  testWidgets('new BOGO form offers exclusive pricing checkboxes', (
    tester,
  ) async {
    await openForm(tester);
    expect(find.text('Fixed price'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<RestaurantDealType>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Buy one, get one free').last);
    await tester.pumpAndSettle();
    expect(checkbox(tester, 'Fixed price').value, isTrue);
    expect(checkbox(tester, 'Price entered at checkout').value, isFalse);
    expect(find.text('Price of one item'), findsOneWidget);

    await tester.tap(find.text('Price entered at checkout'));
    await tester.pumpAndSettle();
    expect(checkbox(tester, 'Fixed price').value, isFalse);
    expect(checkbox(tester, 'Price entered at checkout').value, isTrue);
    expect(find.text('Price of one item'), findsNothing);

    await tester.tap(find.text('Price entered at checkout'));
    await tester.pumpAndSettle();
    expect(checkbox(tester, 'Price entered at checkout').value, isTrue);
    await tester.tap(find.text('Fixed price'));
    await tester.pumpAndSettle();
    expect(checkbox(tester, 'Fixed price').value, isTrue);
    expect(find.text('Price of one item'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing legacy BOGO selects fixed price', (tester) async {
    await openForm(tester, existing: bogo());
    expect(checkbox(tester, 'Fixed price').value, isTrue);
    expect(find.text('Price of one item'), findsOneWidget);
    expect(find.text('95.00'), findsOneWidget);
  });

  testWidgets('editing checkout BOGO restores mode and hides fixed price', (
    tester,
  ) async {
    await openForm(tester, existing: bogo(mode: 'checkout'));
    expect(checkbox(tester, 'Price entered at checkout').value, isTrue);
    expect(find.text('Price of one item'), findsNothing);
    await tester.tap(find.text('Fixed price'));
    await tester.pumpAndSettle();
    expect(find.text('95.00'), findsOneWidget);
  });
}
