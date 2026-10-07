import 'package:flutter/material.dart';
import '../core/constants/deal_categories.dart';
import 'category_entry_banner.dart';

/// Entry point to the Locally Active sport & fitness section.
class LocallyActiveBanner extends StatelessWidget {
  final VoidCallback onTap;
  final int newDealCount;
  final int partnerCount;
  final int dealCount;
  final bool compact;

  const LocallyActiveBanner({
    super.key,
    required this.onTap,
    this.newDealCount = 0,
    this.partnerCount = 0,
    this.dealCount = 0,
    this.compact = false,
  });

  static const Color _skyLight = Color(0xFF81D4FA);
  static const Color _skyMid = Color(0xFF0288D1);
  static const Color _skyDark = Color(0xFF01579B);

  @override
  Widget build(BuildContext context) {
    return CategoryEntryBanner(
      onTap: onTap,
      title: kLocallyActiveCategory,
      subtitle: compact
          ? 'Sport & fitness deals'
          : 'Clubs, coaches and gyms near you',
      icon: Icons.sports_soccer,
      gradientColors: const [_skyLight, _skyMid, _skyDark],
      shadowColor: const Color(0xFF002C4D),
      background: const StickerBomb(stickers: _activeStickers, opacity: 0.18),
      newDealCount: newDealCount,
      partnerCount: partnerCount,
      dealCount: dealCount,
      compact: compact,
    );
  }

  // Hand-placed so the pattern reads evenly and never reflows between builds.
  static const List<BannerSticker> _activeStickers = [
    BannerSticker('⚽', -0.03, -0.28, 27, -0.28),
    BannerSticker('🏀', 0.06, -0.18, 25, 0.22),
    BannerSticker('🎾', 0.15, -0.30, 24, 0.36),
    BannerSticker('🏐', 0.24, -0.18, 26, -0.24),
    BannerSticker('🏋️', 0.33, -0.30, 23, 0.30),
    BannerSticker('🚴', 0.42, -0.18, 24, -0.34),
    BannerSticker('🏃', 0.51, -0.30, 25, 0.18),
    BannerSticker('🏓', 0.60, -0.18, 24, 0.40),
    BannerSticker('🥊', 0.69, -0.30, 23, -0.20),
    BannerSticker('🏈', 0.78, -0.18, 26, 0.26),
    BannerSticker('⚽', 0.87, -0.30, 25, -0.32),
    BannerSticker('🏀', 0.96, -0.18, 24, 0.20),
    BannerSticker('🎾', 0.00, 0.06, 24, 0.32),
    BannerSticker('🏊', 0.09, 0.16, 25, -0.22),
    BannerSticker('🏐', 0.18, 0.06, 23, 0.38),
    BannerSticker('🏋️', 0.27, 0.16, 24, -0.30),
    BannerSticker('🚴', 0.36, 0.06, 23, 0.24),
    BannerSticker('🏃', 0.45, 0.16, 23, -0.36),
    BannerSticker('🏓', 0.54, 0.06, 24, 0.20),
    BannerSticker('🥊', 0.63, 0.16, 26, -0.26),
    BannerSticker('⚽', 0.72, 0.06, 25, 0.34),
    BannerSticker('🏈', 0.81, 0.16, 24, -0.18),
  ];
}
