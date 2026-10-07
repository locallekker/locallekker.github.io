import 'package:flutter/material.dart';
import '../core/constants/deal_categories.dart';
import 'category_entry_banner.dart';

/// Entry point to the Local Sips locally produced wine & alcohol section.
/// Age restricted — the caller gates navigation behind the 18+ confirmation.
class LocalSipsBanner extends StatelessWidget {
  final VoidCallback onTap;
  final int newDealCount;
  final int partnerCount;
  final int dealCount;
  final bool compact;

  const LocalSipsBanner({
    super.key,
    required this.onTap,
    this.newDealCount = 0,
    this.partnerCount = 0,
    this.dealCount = 0,
    this.compact = false,
  });

  static const Color _wineLight = Color(0xFFD4A574);
  static const Color _wineMid = Color(0xFFA64253);
  static const Color _wineDark = Color(0xFF722F37);

  @override
  Widget build(BuildContext context) {
    return CategoryEntryBanner(
      onTap: onTap,
      title: kLocalSipsCategory,
      subtitle: compact
          ? 'Local wines & craft spirits'
          : 'Locally produced wines, beers and craft spirits',
      icon: Icons.wine_bar,
      gradientColors: const [_wineLight, _wineMid, _wineDark],
      shadowColor: const Color(0xFF3E141A),
      background: const StickerBomb(stickers: _sipsStickers, opacity: 0.18),
      tag: '18+',
      newDealCount: newDealCount,
      partnerCount: partnerCount,
      dealCount: dealCount,
      compact: compact,
    );
  }

  // Hand-placed so the pattern reads evenly and never reflows between builds.
  static const List<BannerSticker> _sipsStickers = [
    BannerSticker('🍷', -0.03, -0.28, 27, -0.28),
    BannerSticker('🍾', 0.06, -0.18, 25, 0.22),
    BannerSticker('🥂', 0.15, -0.30, 24, 0.36),
    BannerSticker('🍺', 0.24, -0.18, 26, -0.24),
    BannerSticker('🍸', 0.33, -0.30, 23, 0.30),
    BannerSticker('🍇', 0.42, -0.18, 24, -0.34),
    BannerSticker('🥃', 0.51, -0.30, 25, 0.18),
    BannerSticker('🍹', 0.60, -0.18, 24, 0.40),
    BannerSticker('🍶', 0.69, -0.30, 23, -0.20),
    BannerSticker('🍻', 0.78, -0.18, 26, 0.26),
    BannerSticker('🍷', 0.87, -0.30, 25, -0.32),
    BannerSticker('🍾', 0.96, -0.18, 24, 0.20),
    BannerSticker('🥂', 0.00, 0.06, 24, 0.32),
    BannerSticker('🍺', 0.09, 0.16, 25, -0.22),
    BannerSticker('🍇', 0.18, 0.06, 23, 0.38),
    BannerSticker('🥃', 0.27, 0.16, 24, -0.30),
    BannerSticker('🍸', 0.36, 0.06, 23, 0.24),
    BannerSticker('🍶', 0.45, 0.16, 23, -0.36),
    BannerSticker('🍹', 0.54, 0.06, 24, 0.20),
    BannerSticker('🍻', 0.63, 0.16, 26, -0.26),
    BannerSticker('🍷', 0.72, 0.06, 25, 0.34),
    BannerSticker('🍾', 0.81, 0.16, 24, -0.18),
    BannerSticker('🥂', 0.90, 0.06, 24, 0.28),
    BannerSticker('🍺', 0.99, 0.16, 25, -0.24),
    BannerSticker('🍇', -0.02, 0.38, 23, -0.30),
    BannerSticker('🥃', 0.07, 0.48, 24, 0.26),
    BannerSticker('🍸', 0.16, 0.38, 23, -0.20),
    BannerSticker('🍶', 0.25, 0.48, 23, 0.36),
    BannerSticker('🍹', 0.34, 0.38, 24, -0.28),
    BannerSticker('🍻', 0.43, 0.48, 26, 0.22),
    BannerSticker('🍷', 0.52, 0.38, 25, -0.34),
    BannerSticker('🍾', 0.61, 0.48, 24, 0.30),
    BannerSticker('🥂', 0.70, 0.38, 24, -0.22),
    BannerSticker('🍺', 0.79, 0.48, 25, 0.18),
    BannerSticker('🍇', 0.88, 0.38, 23, -0.32),
    BannerSticker('🥃', 0.97, 0.48, 24, 0.24),
    BannerSticker('🍸', 0.02, 0.70, 23, 0.34),
    BannerSticker('🍶', 0.11, 0.80, 23, -0.26),
    BannerSticker('🍹', 0.20, 0.70, 24, 0.20),
    BannerSticker('🍻', 0.29, 0.80, 26, -0.36),
    BannerSticker('🍷', 0.38, 0.70, 25, 0.28),
    BannerSticker('🍾', 0.47, 0.80, 24, -0.18),
    BannerSticker('🥂', 0.56, 0.70, 24, 0.32),
    BannerSticker('🍺', 0.65, 0.80, 25, -0.24),
    BannerSticker('🍇', 0.74, 0.70, 23, 0.22),
    BannerSticker('🥃', 0.83, 0.80, 24, -0.30),
    BannerSticker('🍸', 0.92, 0.70, 23, 0.26),
    BannerSticker('🍶', 0.05, 0.96, 23, -0.20),
    BannerSticker('🍹', 0.23, 0.96, 24, 0.30),
    BannerSticker('🍻', 0.41, 0.96, 26, -0.28),
    BannerSticker('🍷', 0.59, 0.96, 25, 0.24),
    BannerSticker('🍾', 0.77, 0.96, 24, -0.34),
    BannerSticker('🥂', 0.95, 0.96, 24, 0.18),
  ];
}
