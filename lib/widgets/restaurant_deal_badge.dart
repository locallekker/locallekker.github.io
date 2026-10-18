import 'package:flutter/material.dart';

import '../models/deal_schedule.dart';
import '../models/restaurant_deal.dart';

/// Badge for restaurant deal cards: headline plus serving times when set.
class RestaurantDealBadge extends StatelessWidget {
  final String? dealType;
  final Map<String, dynamic>? customData;
  final Map<String, dynamic>? scheduleData;

  static const Color _color = Color(0xFFB4441F);

  const RestaurantDealBadge({
    super.key,
    required this.dealType,
    this.customData,
    this.scheduleData,
  });

  static IconData iconFor(RestaurantDealType? type) {
    switch (type) {
      case RestaurantDealType.bogo:
        return Icons.looks_two_outlined;
      case RestaurantDealType.setMenu:
        return Icons.menu_book_outlined;
      case RestaurantDealType.kidsFree:
        return Icons.child_care;
      case RestaurantDealType.happyHour:
        return Icons.local_bar_outlined;
      case RestaurantDealType.freeItem:
        return Icons.card_giftcard;
      case RestaurantDealType.group:
        return Icons.groups_outlined;
      case RestaurantDealType.birthday:
        return Icons.cake_outlined;
      case RestaurantDealType.foodPercent:
      case null:
        return Icons.restaurant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = RestaurantDealType.fromKey(dealType);
    final config = type == null ? null : RestaurantDealConfig(type, customData);
    String? when;
    if (scheduleData != null && scheduleData!['type'] == 'weekly') {
      try {
        final schedule = DealSchedule.fromJson(scheduleData!);
        final text = schedule.describe();
        if (text != 'Every day') when = text;
      } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconFor(type), size: 14, color: _color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  config?.headline ?? 'Restaurant deal',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _color,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (config?.bogoPriceAtCheckout == true) ...[
          const SizedBox(height: 4),
          const Text(
            'Cheapest qualifying items free - prices confirmed in store',
            style: TextStyle(fontSize: 11),
          ),
        ],
        if (when != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, size: 12, color: Colors.grey.shade600),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  when,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
