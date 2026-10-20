import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/services/subscription_service.dart';

void main() {
  group('SubscriptionService.oneCalendarMonthFrom', () {
    test('keeps the same day and time of day', () {
      expect(
        SubscriptionService.oneCalendarMonthFrom(DateTime(2025, 2, 8, 14, 30)),
        DateTime(2025, 3, 8, 14, 30),
      );
    });

    test('clamps to the last day of shorter months', () {
      expect(SubscriptionService.oneCalendarMonthFrom(DateTime(2025, 1, 31)), DateTime(2025, 2, 28));
      expect(SubscriptionService.oneCalendarMonthFrom(DateTime(2024, 1, 31)), DateTime(2024, 2, 29));
      expect(SubscriptionService.oneCalendarMonthFrom(DateTime(2025, 3, 31)), DateTime(2025, 4, 30));
    });

    test('rolls over the year in December', () {
      expect(SubscriptionService.oneCalendarMonthFrom(DateTime(2025, 12, 15)), DateTime(2026, 1, 15));
    });
  });

  group('SubscriptionService.addCalendarMonths', () {
    test('matches oneCalendarMonthFrom for a single month', () {
      final from = DateTime(2025, 1, 31, 9);
      expect(SubscriptionService.addCalendarMonths(from, 1), SubscriptionService.oneCalendarMonthFrom(from));
    });

    test('handles multi-year and negative offsets', () {
      expect(SubscriptionService.addCalendarMonths(DateTime(2025, 11, 30), 15), DateTime(2027, 2, 28));
      expect(SubscriptionService.addCalendarMonths(DateTime(2025, 3, 31), -1), DateTime(2025, 2, 28));
      expect(SubscriptionService.addCalendarMonths(DateTime(2025, 1, 10), -13), DateTime(2023, 12, 10));
    });

    test('adding zero months is a no-op', () {
      final from = DateTime(2025, 6, 15, 8, 5);
      expect(SubscriptionService.addCalendarMonths(from, 0), from);
    });
  });
}
