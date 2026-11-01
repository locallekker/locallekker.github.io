import 'dart:math' as math;

import 'deal_schedule.dart';

/// The eight restaurant deal types. Keys match trusted_partner_discounts.deal_type.
/// Server-side twin: public.restaurant_deal_discount (migration
/// 20261018170000_add_bogo_checkout_pricing.sql) — keep the maths in sync.
enum RestaurantDealType {
  foodPercent('restaurant_food_percent', '% Off Food', 'Percentage off the food on the bill'),
  bogo('restaurant_bogo', '2-for-1', 'Buy one, get one free (or buy X get Y)'),
  setMenu('restaurant_set_menu', 'Set Menu', 'A set menu at a special price'),
  kidsFree('restaurant_kids_free', 'Kids Eat Free', 'Free kids meals with paying adults'),
  happyHour('restaurant_happy_hour', 'Happy Hour', '% off selected items at set times'),
  freeItem('restaurant_free_item', 'Free Item', 'A free item with a qualifying order'),
  group('restaurant_group', 'Group Deal', '% off the bill for bigger tables'),
  birthday('restaurant_birthday', 'Birthday Treat', 'A treat in the member\'s birthday week');

  final String key;
  final String label;
  final String helpText;

  const RestaurantDealType(this.key, this.label, this.helpText);

  static const String keyPrefix = 'restaurant_';

  static bool isRestaurantKey(String? dealType) =>
      dealType != null && dealType.trim().toLowerCase().startsWith(keyPrefix);

  static RestaurantDealType? fromKey(String? dealType) {
    final key = dealType?.trim().toLowerCase();
    for (final type in values) {
      if (type.key == key) return type;
    }
    return null;
  }
}

/// Values the member enters when claiming a restaurant deal.
class RestaurantDealInputs {
  final double billTotal;
  final double tip;
  final double excludedAmount;
  final double qualifyingAmount;
  final int itemQty;
  final List<double> itemPrices;
  final int menuQty;
  final int adultQty;
  final int kidQty;
  final int qualifyingQty;
  final int freeQty;
  final int partySize;

  const RestaurantDealInputs({
    required this.billTotal,
    this.tip = 0,
    this.excludedAmount = 0,
    this.qualifyingAmount = 0,
    this.itemQty = 0,
    this.itemPrices = const [],
    this.menuQty = 0,
    this.adultQty = 0,
    this.kidQty = 0,
    this.qualifyingQty = 0,
    this.freeQty = 0,
    this.partySize = 0,
  });

  Map<String, dynamic> toJsonFor(RestaurantDealType type) {
    switch (type) {
      case RestaurantDealType.foodPercent:
        return {'excluded_amount': _r2(excludedAmount)};
      case RestaurantDealType.happyHour:
        return {'qualifying_amount': _r2(qualifyingAmount)};
      case RestaurantDealType.bogo:
        return {
          'item_qty': itemQty,
          if (itemPrices.isNotEmpty) 'item_prices': itemPrices,
        };
      case RestaurantDealType.setMenu:
        return {'menu_qty': menuQty};
      case RestaurantDealType.kidsFree:
        return {'adult_qty': adultQty, 'kid_qty': kidQty};
      case RestaurantDealType.freeItem:
        return {'qualifying_qty': qualifyingQty, 'free_qty': freeQty};
      case RestaurantDealType.group:
        return {'party_size': partySize};
      case RestaurantDealType.birthday:
        return {};
    }
  }
}

class RestaurantDealQuote {
  final double billTotal;
  final double discount;
  final double tip;
  final String summary;
  final String? error;

  const RestaurantDealQuote({
    required this.billTotal,
    required this.discount,
    required this.tip,
    required this.summary,
    this.error,
  });

  bool get isValid => error == null;
  double get total => _r2(billTotal - discount + tip);
}

double _r2(num v) => (v * 100).roundToDouble() / 100;

String formatRand(num v) => 'R${v.toStringAsFixed(2)}';

/// Typed view over a restaurant deal's custom_data.
class RestaurantDealConfig {
  final RestaurantDealType type;
  final Map<String, dynamic> data;

  RestaurantDealConfig(this.type, Map<String, dynamic>? data)
    : data = Map<String, dynamic>.from(data ?? const {});

  double number(String key, [double fallback = 0]) {
    final v = data[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  int integer(String key, [int fallback = 0]) => number(key, fallback.toDouble()).floor();

  String text(String key, [String fallback = '']) {
    final v = data[key]?.toString().trim();
    return (v == null || v.isEmpty) ? fallback : v;
  }

  double get percentage => number('percentage').clamp(0, 100).toDouble();

  int get maxFree => math.max(0, integer('max_free'));
  bool get birthdayIsPercent => text('reward', 'free_item') == 'percent';
  int get birthdayWindowDays => integer('window_days', 3).clamp(0, 31);
  int get minPartySize => math.max(1, integer('min_party_size', 1));
  bool get bogoPriceAtCheckout =>
      type == RestaurantDealType.bogo && text('pricing_mode', 'fixed') == 'checkout';

  String get bogoPricingDescription => bogoPriceAtCheckout
      ? 'Cheapest qualifying items free. Final savings confirmed by the partner in store.'
      : 'Fixed price: ${formatRand(number('item_price'))} per qualifying item.';

  /// One-line headline shown on deal cards.
  String get headline {
    final pct = '${_trim(percentage)}%';
    switch (type) {
      case RestaurantDealType.foodPercent:
        final excluded = text('excluded_label');
        return excluded.isEmpty ? '$pct off food' : '$pct off food (excl. $excluded)';
      case RestaurantDealType.bogo:
        final buy = math.max(1, integer('buy_qty', 1));
        final free = math.max(1, integer('free_qty', 1));
        final item = text('item_name', 'selected items');
        return buy == 1 && free == 1 ? '2-for-1 on $item' : 'Buy $buy get $free free: $item';
      case RestaurantDealType.setMenu:
        return '${text('menu_name', 'Set menu')} for ${formatRand(number('set_price'))}';
      case RestaurantDealType.kidsFree:
        final per = math.max(1, integer('kids_per_adult', 1));
        return per == 1
            ? 'Kids eat free with every paying adult'
            : '$per kids eat free per paying adult';
      case RestaurantDealType.happyHour:
        return '$pct off ${text('item_label', 'selected items')}';
      case RestaurantDealType.freeItem:
        return 'Free ${text('free_item_name', 'item')} with every ${text('qualifying_label', 'qualifying item')}';
      case RestaurantDealType.group:
        return '$pct off for tables of $minPartySize+';
      case RestaurantDealType.birthday:
        return birthdayIsPercent
            ? '$pct off in your birthday week'
            : 'Free ${text('free_item_name', 'treat')} in your birthday week';
    }
  }

  /// Short badge text, e.g. "20% OFF FOOD".
  String get badge {
    final pct = '${_trim(percentage)}%';
    switch (type) {
      case RestaurantDealType.foodPercent:
        return '$pct off food';
      case RestaurantDealType.bogo:
        return '2-for-1';
      case RestaurantDealType.setMenu:
        return 'Set menu ${formatRand(number('set_price'))}';
      case RestaurantDealType.kidsFree:
        return 'Kids eat free';
      case RestaurantDealType.happyHour:
        return 'Happy hour $pct off';
      case RestaurantDealType.freeItem:
        return 'Free ${text('free_item_name', 'item')}';
      case RestaurantDealType.group:
        return 'Groups $minPartySize+ $pct off';
      case RestaurantDealType.birthday:
        return 'Birthday treat';
    }
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// Returns an error message when the partner's settings are incomplete.
  String? validate({required DealSchedule schedule}) {
    switch (type) {
      case RestaurantDealType.foodPercent:
      case RestaurantDealType.group:
        if (percentage <= 0) return 'Enter a percentage between 1 and 100.';
        if (type == RestaurantDealType.group && minPartySize < 2) {
          return 'Minimum table size must be at least 2.';
        }
        return null;
      case RestaurantDealType.happyHour:
        if (percentage <= 0) return 'Enter a percentage between 1 and 100.';
        if (schedule.timeSlots.isEmpty) return 'Add at least one happy hour time slot.';
        return null;
      case RestaurantDealType.bogo:
        if (text('item_name').isEmpty) return 'Enter the item name.';
        if (!['fixed', 'checkout'].contains(text('pricing_mode', 'fixed'))) {
          return 'Choose fixed price or price entered at checkout.';
        }
        if (!bogoPriceAtCheckout &&
            (!number('item_price').isFinite ||
                number('item_price') <= 0 ||
                number('item_price') > 100000 ||
                (number('item_price') * 100 -
                            (number('item_price') * 100).round())
                        .abs() >
                    0.000001)) {
          return 'Enter the price of the free item.';
        }
        if (integer('buy_qty', 1) < 1 ||
            integer('free_qty', 1) < 1 ||
            integer('buy_qty', 1) > 200 ||
            integer('free_qty', 1) > 200 ||
            integer('max_free') < 0 ||
            integer('max_free') > 200) {
          return 'Buy and free quantities must be between 1 and 200; max free must be between 0 and 200.';
        }
        return null;
      case RestaurantDealType.setMenu:
        if (number('set_price') <= 0) return 'Enter the set menu price.';
        if (number('normal_price') <= number('set_price')) {
          return 'The normal price must be higher than the set menu price.';
        }
        return null;
      case RestaurantDealType.kidsFree:
        if (number('kid_meal_value') <= 0) return 'Enter the kids meal value.';
        return null;
      case RestaurantDealType.freeItem:
        if (text('free_item_name').isEmpty) return 'Enter the free item.';
        if (number('free_item_value') <= 0) return 'Enter the value of the free item.';
        return null;
      case RestaurantDealType.birthday:
        if (birthdayIsPercent) {
          if (percentage <= 0) return 'Enter a percentage between 1 and 100.';
        } else {
          if (text('free_item_name').isEmpty) return 'Enter the birthday treat.';
          if (number('free_item_value') <= 0) return 'Enter the value of the treat.';
        }
        return null;
    }
  }

  /// Client-side quote. The database recalculates and rejects mismatches.
  RestaurantDealQuote quote(RestaurantDealInputs inputs) {
    final bill = _r2(inputs.billTotal);
    final tip = _r2(math.max(0.0, inputs.tip));

    RestaurantDealQuote fail(String error) =>
        RestaurantDealQuote(billTotal: bill, discount: 0, tip: tip, summary: '', error: error);

    if (bill <= 0) return fail('Enter your bill total.');
    if (bill > 100000) return fail('Bill total is too high.');
    if (tip > bill) return fail('Tip cannot be more than the bill.');

    final pct = percentage;
    double discount = 0;
    String summary;

    int capped(int free) => maxFree > 0 ? math.min(free, maxFree) : free;

    switch (type) {
      case RestaurantDealType.foodPercent:
        final excluded = _r2(inputs.excludedAmount);
        if (excluded < 0 || excluded > bill) {
          return fail('Excluded items cannot be more than the bill.');
        }
        discount = (bill - excluded) * pct / 100;
        summary = '${_trim(pct)}% off ${formatRand(bill - excluded)} food';
        break;
      case RestaurantDealType.happyHour:
        final qualifying = _r2(inputs.qualifyingAmount);
        if (qualifying < 0 || qualifying > bill) {
          return fail('Happy hour items cannot be more than the bill.');
        }
        discount = qualifying * pct / 100;
        summary = '${_trim(pct)}% off ${formatRand(qualifying)} happy hour items';
        break;
      case RestaurantDealType.bogo:
        final buy = math.max(0, integer('buy_qty', 1));
        final freePer = math.max(0, integer('free_qty', 1));
        final groupSize = buy + freePer;
        final free = capped(groupSize > 0 ? (inputs.itemQty ~/ groupSize) * freePer : 0);
        if (bogoPriceAtCheckout) {
          if (inputs.itemQty < 1 ||
              inputs.itemQty > 200 ||
              inputs.itemPrices.length != inputs.itemQty) {
            return fail('Enter one price for every qualifying item (maximum 200).');
          }
          final prices = inputs.itemPrices;
          if (prices.any((price) =>
              !price.isFinite ||
              price <= 0 ||
              price > 100000 ||
              (price * 100 - (price * 100).round()).abs() > 0.000001)) {
            return fail('Enter valid item prices with at most two decimal places.');
          }
          if (_r2(prices.fold<double>(0, (sum, price) => sum + price)) > bill) {
            return fail('Qualifying item prices cannot exceed the original bill.');
          }
          final sortedPrices = [...prices]..sort();
          discount = sortedPrices.take(free).fold<double>(0, (sum, price) => sum + price);
        } else {
          discount = free * math.max(0.0, number('item_price'));
        }
        summary = '$free free ${text('item_name', 'item')}${free == 1 ? '' : 's'}';
        break;
      case RestaurantDealType.setMenu:
        final saving = math.max(0.0, number('normal_price') - number('set_price'));
        discount = inputs.menuQty * saving;
        summary = '${inputs.menuQty} × ${text('menu_name', 'set menu')}';
        break;
      case RestaurantDealType.kidsFree:
        final per = math.max(1, integer('kids_per_adult', 1));
        final free = capped(math.min(inputs.kidQty, inputs.adultQty * per));
        discount = free * math.max(0.0, number('kid_meal_value'));
        summary = '$free free kids meal${free == 1 ? '' : 's'}';
        break;
      case RestaurantDealType.freeItem:
        final per = math.max(1, integer('free_per_qualifying', 1));
        final free = capped(math.min(inputs.freeQty, inputs.qualifyingQty * per));
        discount = free * math.max(0.0, number('free_item_value'));
        summary = '$free free ${text('free_item_name', 'item')}';
        break;
      case RestaurantDealType.group:
        if (inputs.partySize < minPartySize) {
          return fail('This deal needs a table of at least $minPartySize people.');
        }
        discount = bill * pct / 100;
        summary = 'Table of ${inputs.partySize}: ${_trim(pct)}% off';
        break;
      case RestaurantDealType.birthday:
        if (birthdayIsPercent) {
          discount = bill * pct / 100;
          summary = 'Birthday: ${_trim(pct)}% off';
        } else {
          discount = math.max(0.0, number('free_item_value'));
          summary = 'Birthday: free ${text('free_item_name', 'treat')}';
        }
        break;
    }

    for (final qty in [
      inputs.itemQty, inputs.menuQty, inputs.adultQty, inputs.kidQty,
      inputs.qualifyingQty, inputs.freeQty, inputs.partySize,
    ]) {
      if (qty < 0 || qty > 200) return fail('Please check the numbers you entered.');
    }

    discount = _r2(math.min(math.max(discount, 0), bill));
    return RestaurantDealQuote(billTotal: bill, discount: discount, tip: tip, summary: summary);
  }

  /// Birthday window check against a date of birth (SAST dates, ±window days).
  bool isWithinBirthdayWindow(DateTime dateOfBirth, DateTime now) {
    final today = DealSchedule.sastWallClock(now);
    final todayDate = DateTime.utc(today.year, today.month, today.day);
    final dobSast = dateOfBirth.isUtc ? DealSchedule.sastWallClock(dateOfBirth) : dateOfBirth;
    for (final year in [today.year - 1, today.year, today.year + 1]) {
      final lastDay = DateTime.utc(year, dobSast.month + 1, 0).day;
      final bday = DateTime.utc(year, dobSast.month, math.min(dobSast.day, lastDay));
      if (todayDate.difference(bday).inDays.abs() <= birthdayWindowDays) return true;
    }
    return false;
  }
}

/// Builds the bill_data stored on deal_authorizations for restaurant deals.
/// Uses the same top-level keys as bill discounts so savings reports work.
Map<String, dynamic> buildRestaurantBillData({
  required RestaurantDealType type,
  required RestaurantDealInputs inputs,
  required RestaurantDealQuote quote,
}) {
  return {
    'original_bill_amount': quote.billTotal,
    'discount_amount': quote.discount,
    'tip_amount': quote.tip,
    'final_amount': quote.total,
    'excluded_items_total': type == RestaurantDealType.foodPercent ? _r2(inputs.excludedAmount) : 0,
    'restaurant': {
      'type': type.key,
      'inputs': inputs.toJsonFor(type),
      'summary': quote.summary,
    },
  };
}
