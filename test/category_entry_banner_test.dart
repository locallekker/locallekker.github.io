import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/widgets/category_entry_banner.dart';
import 'package:local_lekker/widgets/member_category_banner_row.dart';

void main() {
  for (final width in [360.0, 720.0]) {
    testWidgets('category content is centred within each banner at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tapped = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: MemberCategoryBannerRow(
                onTapPartners: () => tapped.add('Partners'),
                partnerCount: 64,
                dealCount: 102,
                showFreshLocal: true,
                onTapFreshLocal: () => tapped.add('Fresh & Local'),
                freshPartnerCount: 1,
                freshDealCount: 1,
                showLocalSips: true,
                onTapLocalSips: () => tapped.add('Local Sips'),
                sipsPartnerCount: 2,
                sipsDealCount: 3,
                showLocalEats: true,
                onTapLocalEats: () => tapped.add('Local Eats'),
                eatsPartnerCount: 9,
                eatsDealCount: 19,
                showLocallyActive: true,
                onTapLocallyActive: () => tapped.add('Locally Active'),
                activePartnerCount: 3,
                activeDealCount: 4,
              ),
            ),
          ),
        ),
      );

      final banners = find.byType(CategoryEntryBanner);
      expect(banners, findsNWidgets(5));

      for (var index = 0; index < 5; index++) {
        final banner = banners.at(index);
        final widget = tester.widget<CategoryEntryBanner>(banner);
        final card = find.descendant(
          of: banner,
          matching: find.byType(InkWell),
        );
        final cardRect = tester.getRect(card);
        final icon = find.descendant(
          of: banner,
          matching: find.byIcon(widget.icon),
        );
        final title = find.descendant(
          of: banner,
          matching: find.text(widget.title),
        );
        final subtitle = find.descendant(
          of: banner,
          matching: find.text(widget.subtitle),
        );
        final counts = find.descendant(
          of: banner,
          matching: find.byWidgetPredicate(
            (child) =>
                child is Text && (child.data?.contains(' deal') ?? false),
          ),
        );

        for (final content in [icon, title, subtitle, counts]) {
          expect(
            tester.getCenter(content).dx,
            closeTo(cardRect.center.dx, 0.1),
            reason: '${widget.title} content must share the banner centre',
          );
        }

        final circleRect = tester.getRect(
          find.ancestor(of: icon, matching: find.byType(Container)).first,
        );
        final contentCentreY =
            (circleRect.top + tester.getRect(counts).bottom) / 2;
        expect(contentCentreY, closeTo(cardRect.center.dy, 0.1));

        await tester.tap(title);
        expect(tapped.last, widget.title);
      }

      expect(find.text('18+'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
