import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/main.dart';

void main() {
  group('App Integration Tests', () {
    test('App builds successfully', () {
      // Test that the main app widget can be instantiated
      const app = LocalLekkerApp();
      expect(app, isNotNull);
      expect(app.key, isNull); // Default key should be null
    });

    test('App has proper widget structure', () {
      const app = LocalLekkerApp();
      // Test that it's a StatefulWidget
      expect(app, isA<StatefulWidget>());
    });
  });

  group('Build Verification', () {
    testWidgets('App widget tree builds without crashing', (
      WidgetTester tester,
    ) async {
      // This test just verifies that the app can be pumped without immediate crashes
      // We don't test specific UI elements since they depend on services
      await tester.pumpWidget(const LocalLekkerApp());

      // Just verify that some widget was built (the app didn't crash immediately)
      expect(find.byType(LocalLekkerApp), findsOneWidget);
    });
  });
}
