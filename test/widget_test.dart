import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/main.dart';
import 'package:local_lekker/widgets/loading_screen.dart';

void main() {
  testWidgets('App builds and shows loading screen initially', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LocalLekkerApp());
    expect(find.byType(LoadingScreen), findsOneWidget);
  });
}
