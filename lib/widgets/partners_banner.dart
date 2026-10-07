import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import 'category_entry_banner.dart';

/// Entry point to the full trusted partner directory. Always shown, and
/// stretches to fill the row when no curated category banners are available.
class PartnersBanner extends StatelessWidget {
  final VoidCallback onTap;
  final int partnerCount;
  final int dealCount;
  final bool compact;

  const PartnersBanner({
    super.key,
    required this.onTap,
    this.partnerCount = 0,
    this.dealCount = 0,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return CategoryEntryBanner(
      onTap: onTap,
      title: 'Partners',
      subtitle: compact
          ? 'Browse all partners'
          : 'Browse every Local Lekker trusted partner near you',
      icon: Icons.storefront_outlined,
      gradientColors: const [
        AppColors.skyLight,
        AppColors.sky,
        AppColors.oceanDeep,
      ],
      shadowColor: const Color(0xFF073A63),
      background: const StickerBomb(stickers: _partnerStickers, opacity: 0.16),
      partnerCount: partnerCount,
      dealCount: dealCount,
      compact: compact,
    );
  }

  static const List<BannerSticker> _partnerStickers = [
    BannerSticker('🏪', -0.02, -0.28, 26, -0.26),
    BannerSticker('🛍️', 0.08, -0.18, 24, 0.24),
    BannerSticker('🏷️', 0.18, -0.30, 23, 0.34),
    BannerSticker('☕', 0.28, -0.18, 24, -0.22),
    BannerSticker('💈', 0.38, -0.30, 23, 0.30),
    BannerSticker('🍽️', 0.48, -0.18, 24, -0.32),
    BannerSticker('💐', 0.58, -0.30, 23, 0.20),
    BannerSticker('🧁', 0.68, -0.18, 24, 0.38),
    BannerSticker('🏬', 0.78, -0.30, 25, -0.20),
    BannerSticker('🎁', 0.88, -0.18, 23, 0.26),
    BannerSticker('🛒', 0.98, -0.30, 24, -0.30),
    BannerSticker('🏪', 0.02, 0.08, 26, 0.30),
    BannerSticker('🛍️', 0.12, 0.18, 24, -0.24),
    BannerSticker('🏷️', 0.22, 0.08, 23, 0.36),
    BannerSticker('☕', 0.32, 0.18, 24, -0.28),
    BannerSticker('💈', 0.42, 0.08, 23, 0.22),
    BannerSticker('🍽️', 0.52, 0.18, 24, -0.34),
    BannerSticker('💐', 0.62, 0.08, 23, 0.26),
    BannerSticker('🧁', 0.72, 0.18, 24, -0.20),
    BannerSticker('🏬', 0.82, 0.08, 25, 0.32),
    BannerSticker('🎁', 0.92, 0.18, 23, -0.26),
    BannerSticker('🛒', -0.03, 0.42, 24, 0.20),
    BannerSticker('🏪', 0.07, 0.52, 26, -0.32),
    BannerSticker('🛍️', 0.17, 0.42, 24, 0.28),
    BannerSticker('🏷️', 0.27, 0.52, 23, -0.22),
    BannerSticker('☕', 0.37, 0.42, 24, 0.34),
    BannerSticker('💈', 0.47, 0.52, 23, -0.30),
    BannerSticker('🍽️', 0.57, 0.42, 24, 0.24),
    BannerSticker('💐', 0.67, 0.52, 23, -0.36),
    BannerSticker('🧁', 0.77, 0.42, 24, 0.18),
    BannerSticker('🏬', 0.87, 0.52, 25, -0.24),
    BannerSticker('🎁', 0.97, 0.42, 23, 0.30),
    BannerSticker('🛒', 0.03, 0.74, 24, -0.28),
    BannerSticker('🏪', 0.13, 0.84, 26, 0.22),
    BannerSticker('🛍️', 0.23, 0.74, 24, -0.34),
    BannerSticker('🏷️', 0.33, 0.84, 23, 0.26),
    BannerSticker('☕', 0.43, 0.74, 24, -0.20),
    BannerSticker('💈', 0.53, 0.84, 23, 0.32),
    BannerSticker('🍽️', 0.63, 0.74, 24, -0.26),
    BannerSticker('💐', 0.73, 0.84, 23, 0.20),
    BannerSticker('🧁', 0.83, 0.74, 24, -0.30),
    BannerSticker('🏬', 0.93, 0.84, 25, 0.24),
    BannerSticker('🎁', 0.08, 0.96, 23, -0.22),
    BannerSticker('🛒', 0.30, 0.96, 24, 0.28),
    BannerSticker('🏪', 0.52, 0.96, 26, -0.32),
    BannerSticker('🛍️', 0.74, 0.96, 24, 0.20),
    BannerSticker('🏷️', 0.94, 0.96, 23, -0.26),
  ];
}
