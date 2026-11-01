import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/widgets/deal_image_preview.dart';

Future<void> openPreview(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => const DealImagePreview(
                imageUrl: 'https://example.com/deal.png',
                dealName: 'Member deal',
              ),
            ),
            child: const Text('Deal image'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Deal image'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('expands and minimises using the icon', (tester) async {
    await openPreview(tester);

    expect(find.byType(DealImagePreview), findsOneWidget);
    expect(find.text('Member deal'), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);

    await tester.tap(find.byTooltip('Minimise image'));
    await tester.pumpAndSettle();

    expect(find.byType(DealImagePreview), findsNothing);
    expect(find.text('Deal image'), findsOneWidget);
  });

  testWidgets('tapping the expanded image minimises it', (tester) async {
    await openPreview(tester);

    await tester.tap(find.byType(InteractiveViewer));
    await tester.pumpAndSettle();

    expect(find.byType(DealImagePreview), findsNothing);
    expect(find.text('Deal image'), findsOneWidget);
  });

  testWidgets('dragging the image does not minimise it', (tester) async {
    await openPreview(tester);

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.minScale, 1);
    expect(viewer.maxScale, 4);

    await tester.drag(find.byType(InteractiveViewer), const Offset(40, 0));
    await tester.pumpAndSettle();

    expect(find.byType(DealImagePreview), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview fits a small member screen', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openPreview(tester);

    expect(find.byTooltip('Minimise image'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
