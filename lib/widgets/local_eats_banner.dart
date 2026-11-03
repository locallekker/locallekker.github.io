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
        subtitle: compact
          ? 'Restaurants, cafes & takeaways'
          : 'Local food and drink spots',
      icon: Icons.restaurant,
      gradientColors: const [
        Color(0xFFFFB347),
        Color(0xFFF0643A),
        Color(0xFFB83227),
      ],
      shadowColor: const Color(0xFF642218),
      background: const StickerBomb(
        stickers: [
          BannerSticker('🍽️', 0.02, -0.28, 26, -0.26),
          BannerSticker('🍔', 0.11, -0.18, 25, 0.24),
          BannerSticker('🥗', 0.20, -0.30, 24, 0.34),
          BannerSticker('🍜', 0.29, -0.18, 27, -0.22),
          BannerSticker('🍕', 0.38, -0.28, 25, 0.30),
          BannerSticker('☕', 0.47, -0.18, 24, -0.32),
          BannerSticker('🍰', 0.56, -0.30, 25, 0.20),
          BannerSticker('🍟', 0.65, -0.18, 24, 0.38),
          BannerSticker('🌮', 0.74, -0.28, 26, -0.20),
          BannerSticker('🥪', 0.83, -0.18, 25, 0.26),
          BannerSticker('🍲', 0.92, -0.30, 24, -0.30),
          BannerSticker('🥐', 0.00, 0.08, 25, 0.30),
          BannerSticker('🍣', 0.09, 0.18, 24, -0.24),
          BannerSticker('🍩', 0.18, 0.08, 25, 0.36),
          BannerSticker('🍛', 0.27, 0.18, 24, -0.28),
          BannerSticker('🥞', 0.36, 0.08, 25, 0.22),
          BannerSticker('🍗', 0.45, 0.18, 24, -0.34),
          BannerSticker('🧁', 0.54, 0.08, 25, 0.26),
          BannerSticker('🥙', 0.63, 0.18, 24, -0.20),
          BannerSticker('🍝', 0.72, 0.08, 26, 0.32),
          BannerSticker('🥤', 0.81, 0.18, 24, -0.26),
          BannerSticker('🥘', 0.90, 0.08, 25, 0.30),
          BannerSticker('🍱', 0.03, 0.42, 25, 0.20),
          BannerSticker('🍦', 0.12, 0.52, 24, -0.32),
          BannerSticker('🧇', 0.21, 0.42, 25, 0.28),
          BannerSticker('🥧', 0.30, 0.52, 24, -0.22),
          BannerSticker('🍤', 0.39, 0.42, 25, 0.34),
          BannerSticker('🍿', 0.48, 0.52, 24, -0.30),
          BannerSticker('🫔', 0.57, 0.42, 25, 0.24),
          BannerSticker('🍖', 0.66, 0.52, 24, -0.36),
          BannerSticker('🧋', 0.75, 0.42, 25, 0.18),
          BannerSticker('🥨', 0.84, 0.52, 24, -0.24),
          BannerSticker('🍚', 0.93, 0.42, 25, 0.30),
          BannerSticker('🍪', 0.00, 0.74, 24, -0.28),
          BannerSticker('🥬', 0.09, 0.84, 25, 0.22),
          BannerSticker('🍅', 0.18, 0.74, 24, -0.34),
          BannerSticker('🥑', 0.27, 0.84, 25, 0.26),
          BannerSticker('🍋', 0.36, 0.74, 24, -0.20),
          BannerSticker('🍓', 0.45, 0.84, 25, 0.32),
          BannerSticker('🥕', 0.54, 0.74, 24, -0.26),
          BannerSticker('🍉', 0.63, 0.84, 25, 0.20),
          BannerSticker('🧀', 0.72, 0.74, 24, -0.30),
          BannerSticker('🥦', 0.81, 0.84, 25, 0.24),
          BannerSticker('🍊', 0.90, 0.74, 24, -0.26),
          BannerSticker('🍇', 0.08, 0.96, 24, -0.22),
          BannerSticker('🥥', 0.28, 0.96, 25, 0.28),
          BannerSticker('🍍', 0.48, 0.96, 24, -0.32),
          BannerSticker('🫒', 0.68, 0.96, 25, 0.20),
          BannerSticker('🍒', 0.88, 0.96, 24, -0.26),
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
