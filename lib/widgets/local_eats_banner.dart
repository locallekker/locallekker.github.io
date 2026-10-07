import 'package:flutter/material.dart';
import '../core/constants/deal_categories.dart';
import 'category_entry_banner.dart';

/// Member entry point for food and beverage partners.
class LocalEatsBanner extends StatelessWidget {
  final VoidCallback onTap;
  final int newDealCount;
  final int partnerCount;
  final int dealCount;
  final bool compact;

  const LocalEatsBanner({
    super.key,
    required this.onTap,
    this.newDealCount = 0,
    this.partnerCount = 0,
    this.dealCount = 0,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return CategoryEntryBanner(
      onTap: onTap,
      title: kLocalEatsCategory,
      subtitle: compact ? 'Food deals near you' : 'Local food and drink spots',
      icon: Icons.restaurant,
      gradientColors: const [
        Color(0xFFFFB347),
        Color(0xFFF0643A),
        Color(0xFFB83227),
      ],
      shadowColor: const Color(0xFF642218),
      background: const StickerBomb(
        stickers: [
          BannerSticker('🍽️', 0.08, 0.10, 27, -0.18),
          BannerSticker('🍔', 0.35, 0.32, 30, 0.20),
          BannerSticker('🥗', 0.63, 0.12, 28, -0.24),
          BannerSticker('🍜', 0.87, 0.38, 29, 0.16),
        ],
        opacity: 0.2,
      ),
      newDealCount: newDealCount,
      partnerCount: partnerCount,
      dealCount: dealCount,
      compact: compact,
    );
  }
}
