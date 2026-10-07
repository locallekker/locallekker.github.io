import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:local_lekker/core/theme/app_colors.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../core/constants/deal_categories.dart';
import '../../services/discount_service.dart';
import '../auth/trusted_partner_shop_page.dart';

const Color _wineDark = Color(0xFF722F37);
const Color _wineRed = Color(0xFF7A2E3F);

/// Member listing of trusted partners that sell locally produced alcohol.
/// Entry is gated behind the 18+ confirmation (see ensureMemberIsAgeVerified).
class LocalSipsPartnersPage extends StatefulWidget {
  final String? cityFilter;

  const LocalSipsPartnersPage({super.key, this.cityFilter});

  @override
  State<LocalSipsPartnersPage> createState() => _LocalSipsPartnersPageState();
}

class _LocalSipsPartnersPageState extends State<LocalSipsPartnersPage> {
  final DiscountService _discountService = DiscountService();
  List<Map<String, dynamic>> _partners = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPartners();
  }

  Future<void> _loadPartners() async {
    setState(() => _isLoading = true);
    final partners = await _discountService.getLocalSipsPartners(
      city: widget.cityFilter,
    );
    if (!mounted) return;
    setState(() {
      _partners = partners;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BrandedAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wine_bar, size: 22),
            SizedBox(width: 8),
            Text(kLocalSipsCategory),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadPartners,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _partners.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                      itemCount: _partners.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (index == 0) return _buildIntro();
                        return _buildPartnerCard(_partners[index - 1]);
                      },
                    ),
            ),
          ),
          _buildLegalFooter(),
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _wineRed,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // Sticker bomb background
          Positioned.fill(
            child: _buildAlcoholStickerBomb(),
          ),
          // Content on top
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Locally Produced Spirits',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Discover craft wines, beers & spirits from artisan makers near you.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlcoholStickerBomb() {
    return CustomPaint(
      painter: AlcoholStickerBombPainter(),
      child: Container(),
    );
  }


  Widget _buildLegalFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: _wineDark.withValues(alpha: 0.08),
      child: const Text(
        '18+ only. Drink responsibly. Not for sale to persons under the age of 18.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: _wineDark,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.wine_bar_outlined, size: 64, color: AppColors.textSecondary),
        const SizedBox(height: 16),
        const Text(
          'No Local Sips partners yet',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          widget.cityFilter == null
              ? 'Check back soon.'
              : 'No partners in ${widget.cityFilter}. Try changing your area.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildPartnerCard(Map<String, dynamic> partner) {
    final name = (partner['name'] as String?) ?? 'Partner';
    final description = (partner['alcohol_description'] as String?)?.trim();
    final logoUrl = (partner['logo_url'] as String?)?.trim();
    final city = (partner['city'] as String?)?.trim();
    final dealCount = (partner['deal_count'] as int?) ?? 0;
    final delivers = (partner['offers_delivery'] as bool?) ?? false;
    final licensed = (partner['liquor_license_verified'] as bool?) ?? false;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TrustedPartnerShopPage(partner: partner),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.outline),
          boxShadow: [
            BoxShadow(
              color: _wineDark.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLogo(logoUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildChip(
                        Icons.local_offer_outlined,
                        dealCount == 1 ? '1 item' : '$dealCount items',
                        AppColors.accent,
                      ),
                      if (city != null && city.isNotEmpty)
                        _buildChip(
                          Icons.location_on_outlined,
                          city,
                          AppColors.primary,
                        ),
                      if (delivers)
                        _buildChip(
                          Icons.delivery_dining,
                          'Delivers',
                          AppColors.success,
                        ),
                      if (licensed)
                        _buildChip(
                          Icons.verified_outlined,
                          'Licensed',
                          _wineDark,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo(String? logoUrl) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: _wineDark.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl == null || logoUrl.isEmpty
          ? const Icon(Icons.storefront_outlined, color: _wineDark)
          : Image.network(
              logoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.storefront_outlined, color: _wineDark),
            ),
    );
  }

  Widget _buildChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for alcohol sticker bomb background
class AlcoholStickerBombPainter extends CustomPainter {
  static const double _opacity = 0.2;
  
  final List<({
    IconData icon,
    double x,
    double y,
    double angle,
    double size,
  })> stickers = [];

  AlcoholStickerBombPainter() {
    // Generate random stickers with seed for consistent layout
    final random = math.Random(42);
    const iconList = [
      Icons.wine_bar,
      Icons.local_bar,
      Icons.emoji_food_beverage,
      Icons.bubble_chart,
      Icons.grain,
    ];

    for (int i = 0; i < 20; i++) {
      stickers.add((
        icon: iconList[i % iconList.length],
        x: random.nextDouble(),
        y: random.nextDouble(),
        angle: random.nextDouble() * 2 * math.pi,
        size: 20 + random.nextDouble() * 30,
      ));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final sticker in stickers) {
      _drawIcon(
        canvas,
        sticker.icon,
        size.width * sticker.x,
        size.height * sticker.y,
        sticker.angle,
        sticker.size,
      );
    }
  }

  void _drawIcon(
    Canvas canvas,
    IconData icon,
    double x,
    double y,
    double angle,
    double size,
  ) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: _opacity)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);

    // Draw a simple icon representation
    _drawIconData(canvas, icon, size, paint);

    canvas.restore();
  }

  void _drawIconData(Canvas canvas, IconData icon, double size, Paint paint) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: paint.color,
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(-size / 2, -size / 2));
  }

  @override
  bool shouldRepaint(AlcoholStickerBombPainter oldDelegate) => false;
}
