import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/models/restaurant_deal.dart';
import 'package:local_lekker/models/deal_schedule.dart';

// Mirrors the live database checks in restaurant_deal_discount() so the
// in-app breakdown always matches what the server will accept.
void main() {
  RestaurantDealConfig cfg(RestaurantDealType t, Map<String, dynamic> d) =>
      RestaurantDealConfig(t, d);

  test('% off food excludes drinks', () {
    final q = cfg(RestaurantDealType.foodPercent, {'percentage': 20})
        .quote(const RestaurantDealInputs(billTotal: 500, excludedAmount: 100, tip: 50));
    expect(q.discount, 80);
    expect(q.total, 470);
  });

  test('2-for-1 respects max free', () {
    final q = cfg(RestaurantDealType.bogo,
            {'item_price': 95, 'buy_qty': 1, 'free_qty': 1, 'max_free': 2})
        .quote(const RestaurantDealInputs(billTotal: 600, itemQty: 5));
    expect(q.discount, 190);
  });

  group('BOGO pricing modes', () {
    RestaurantDealConfig checkout({int maxFree = 0, int buy = 1, int free = 1}) =>
        cfg(RestaurantDealType.bogo, {
          'item_name': 'cocktails',
          'pricing_mode': 'checkout',
          'buy_qty': buy,
          'free_qty': free,
          'max_free': maxFree,
        });

    test('legacy deals default to fixed and checkout mode needs no fixed price', () {
      final legacy = cfg(RestaurantDealType.bogo, {
        'item_name': 'burgers', 'item_price': 80,
      });
      expect(legacy.bogoPriceAtCheckout, isFalse);
      expect(legacy.validate(schedule: DealSchedule(type: ScheduleType.weekly)), isNull);
      expect(checkout().validate(schedule: DealSchedule(type: ScheduleType.weekly)), isNull);
      expect(
        cfg(RestaurantDealType.bogo, {
          'item_name': 'burgers', 'pricing_mode': 'fixed',
        }).validate(schedule: DealSchedule(type: ScheduleType.weekly)),
        isNotNull,
      );
      expect(
        cfg(RestaurantDealType.bogo, {
          'item_name': 'burgers', 'pricing_mode': 'unknown',
        }).validate(schedule: DealSchedule(type: ScheduleType.weekly)),
        isNotNull,
      );
    });

    test('cheaper R75 cocktail is free and extras/tip are preserved', () {
      final q = checkout().quote(const RestaurantDealInputs(
        billTotal: 200, tip: 20, itemQty: 2, itemPrices: [95, 75],
      ));
      expect(q.isValid, isTrue);
      expect(q.discount, 75);
      expect(q.total, 145);
    });

    test('discounts cheapest items regardless of entry order', () {
      for (final prices in <List<double>>[
        [120, 60, 100, 80],
        [80, 100, 60, 120],
      ]) {
        final q = checkout().quote(RestaurantDealInputs(
          billTotal: 360, itemQty: 4, itemPrices: prices,
        ));
        expect(q.discount, 140);
        expect(q.total, 220);
      }
    });

    test('honours max-free, incomplete groups, buy-X-get-Y, and cents', () {
      const inputs = RestaurantDealInputs(
        billTotal: 500, itemQty: 5, itemPrices: [99.95, 80.10, 70.05, 100, 100],
      );
      expect(checkout(maxFree: 1).quote(inputs).discount, 70.05);
      expect(checkout().quote(inputs).discount, 150.15);
      expect(checkout(buy: 2, free: 1).quote(inputs).discount, 70.05);
      expect(checkout(buy: 1, free: 2).quote(inputs).discount, 150.15);
    });

    test('rejects missing, mismatched, invalid, or excessive prices', () {
      for (final prices in <List<double>>[
        [],
        [95],
        [95, 75, 60],
        [95, 0],
        [95, -75],
        [95, double.nan],
        [95, double.infinity],
        [95, 75.001],
        [95, 100001],
        [95, 150],
      ]) {
        expect(checkout().quote(RestaurantDealInputs(
          billTotal: 200, itemQty: 2, itemPrices: prices,
        )).isValid, isFalse, reason: '$prices');
      }
      expect(checkout().quote(RestaurantDealInputs(
        billTotal: 500, itemQty: 201, itemPrices: List.filled(201, 1),
      )).isValid, isFalse);
    });

    test('fixed pricing ignores entered prices', () {
      final q = cfg(RestaurantDealType.bogo, {
        'pricing_mode': 'fixed', 'item_price': 80,
      }).quote(const RestaurantDealInputs(
        billTotal: 200, itemQty: 2, itemPrices: [95, 75],
      ));
      expect(q.discount, 80);
    });

    test('checkout prices are included in stored bill details', () {
      const inputs = RestaurantDealInputs(
        billTotal: 170, itemQty: 2, itemPrices: [95, 75],
      );
      final data = buildRestaurantBillData(
        type: RestaurantDealType.bogo,
        inputs: inputs,
        quote: checkout().quote(inputs),
      );
      expect(data['discount_amount'], 75);
      expect(data['final_amount'], 95);
      expect(data['restaurant']['inputs'], {
        'item_qty': 2, 'item_prices': [95.0, 75.0],
      });
    });
  });

  test('set menu saving per menu', () {
    final q = cfg(RestaurantDealType.setMenu, {'set_price': 199, 'normal_price': 260})
        .quote(const RestaurantDealInputs(billTotal: 600, menuQty: 2));
    expect(q.discount, 122);
  });

  test('kids eat free limited by adults', () {
    final q = cfg(RestaurantDealType.kidsFree, {'kids_per_adult': 1, 'kid_meal_value': 80})
        .quote(const RestaurantDealInputs(billTotal: 700, adultQty: 2, kidQty: 3));
    expect(q.discount, 160);
  });

  test('free item limited by qualifying items', () {
    final q = cfg(RestaurantDealType.freeItem, {'free_item_value': 65, 'free_per_qualifying': 1})
        .quote(const RestaurantDealInputs(billTotal: 700, qualifyingQty: 3, freeQty: 2));
    expect(q.discount, 130);
  });

  test('group deal needs minimum table size', () {
    final c = cfg(RestaurantDealType.group, {'percentage': 10, 'min_party_size': 6});
    expect(c.quote(const RestaurantDealInputs(billTotal: 2000, partySize: 8)).discount, 200);
    expect(c.quote(const RestaurantDealInputs(billTotal: 2000, partySize: 4)).error, isNotNull);
  });

  test('happy hour discounts only qualifying items', () {
    final q = cfg(RestaurantDealType.happyHour, {'percentage': 50})
        .quote(const RestaurantDealInputs(billTotal: 300, qualifyingAmount: 120));
    expect(q.discount, 60);
  });

  test('birthday treat and window', () {
    final c = cfg(RestaurantDealType.birthday,
        {'reward': 'free_item', 'free_item_value': 120, 'window_days': 3});
    expect(c.quote(const RestaurantDealInputs(billTotal: 400)).discount, 120);

    final now = DateTime.utc(2026, 10, 19, 10);
    expect(c.isWithinBirthdayWindow(DateTime(1996, 10, 21), now), isTrue);
    expect(c.isWithinBirthdayWindow(DateTime(1996, 10, 29), now), isFalse);
  });

  test('discount never exceeds bill', () {
    final q = cfg(RestaurantDealType.setMenu, {'set_price': 100, 'normal_price': 500})
        .quote(const RestaurantDealInputs(billTotal: 300, menuQty: 2));
    expect(q.discount, 300);
  });
}
